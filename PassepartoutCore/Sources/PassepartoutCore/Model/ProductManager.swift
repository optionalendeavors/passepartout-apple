//
//  ProductManager.swift
//  Passepartout
//
//  Created by Davide De Rosa on 4/6/19.
//  Copyright (c) 2021 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import StoreKit
import Convenience
import SwiftyBeaver
import Kvitto
import TunnelKitCore
import TunnelKitManager
import PassepartoutConstants

private let log = SwiftyBeaver.self

public enum ProductError: Error {
    case uneligible
    
    case beta
}

public class ProductManager: NSObject {
    public struct Configuration {
        public let locksBetaFeatures: Bool
        
        public let isBetaFullVersion: Bool

        public let lastFullVersionBuild: (Int, LocalProduct)
        
        public init(
            locksBetaFeatures: Bool,
            isBetaFullVersion: Bool,
            lastFullVersionBuild: (Int, LocalProduct)
        ) {
            self.locksBetaFeatures = locksBetaFeatures
            self.isBetaFullVersion = isBetaFullVersion
            self.lastFullVersionBuild = lastFullVersionBuild
        }
    }
    
    public static let didReloadReceipt = Notification.Name("ProductManagerDidReloadReceipt")
    
    public static let didReviewPurchases = Notification.Name("ProductManagerDidReviewPurchases")
    
    public let cfg: Configuration

    private let inApp: InApp<LocalProduct>
    
    private var purchasedAppBuild: Int?
    
    private var purchasedFeatures: Set<LocalProduct>
    
    private var purchaseDates: [LocalProduct: Date]
    
    private var cancelledPurchases: Set<LocalProduct>
    
    private var refreshRequest: SKReceiptRefreshRequest?
    
    private var restoreCompletionHandler: ((Error?) -> Void)?
    
    public init(_ cfg: Configuration) {
        self.cfg = cfg
        inApp = InApp()
        purchasedAppBuild = nil
        purchasedFeatures = []
        purchaseDates = [:]
        cancelledPurchases = []
        
        super.init()

        reloadReceipt()
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    public var isBeta: Bool {
        #if os(iOS)
        #if targetEnvironment(simulator)
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
        #else
        // For the locally built version, we'll say that we're a beta version.
        return true
//        return false
        #endif
    }

    public func listProducts(completionHandler: (([SKProduct]?, Error?) -> Void)?) {
        let products = LocalProduct.all
        guard !products.isEmpty else {
            completionHandler?(nil, nil)
            return
        }
        inApp.requestProducts(withIdentifiers: products, completionHandler: { _ in
            log.debug("In-app products: \(self.inApp.products.map { $0.productIdentifier })")

            completionHandler?(self.inApp.products, nil)
        }, failureHandler: {
            completionHandler?(nil, $0)
        })
    }

    public func product(withIdentifier identifier: LocalProduct) -> SKProduct? {
        return inApp.product(withIdentifier: identifier)
    }
    
    public func featureProducts(including: [LocalProduct]) -> [SKProduct] {
        return inApp.products.filter {
            guard let p = LocalProduct(rawValue: $0.productIdentifier) else {
                return false
            }
            guard including.contains(p) else {
                return false
            }
            guard p.isFeature else {
                return false
            }
            return true
        }
    }
    
    public func featureProducts(excluding: [LocalProduct]) -> [SKProduct] {
        return inApp.products.filter {
            guard let p = LocalProduct(rawValue: $0.productIdentifier) else {
                return false
            }
            guard !excluding.contains(p) else {
                return false
            }
            guard p.isFeature else {
                return false
            }
            return true
        }
    }
    
    public func purchase(_ product: SKProduct, completionHandler: @escaping (InAppPurchaseResult, Error?) -> Void) {
        inApp.purchase(product: product) {
            if $0 == .success {
                self.reloadReceipt()
            }
            completionHandler($0, $1)
        }
    }
    
    public func restorePurchases(completionHandler: @escaping (Error?) -> Void) {
        restoreCompletionHandler = completionHandler
        refreshRequest = SKReceiptRefreshRequest()
        refreshRequest?.delegate = self
        refreshRequest?.start()
    }

    // MARK: In-app eligibility
    
    private func isCurrentPlatformVersion() -> Bool {
        #if os(iOS)
        return purchasedFeatures.contains(.fullVersion_iOS)
        #else
        return purchasedFeatures.contains(.fullVersion_macOS)
        #endif
    }

    private func isFullVersion() -> Bool {
        if isBeta && cfg.isBetaFullVersion {
            return true
        }
        if isCurrentPlatformVersion() {
            return true
        }
        return purchasedFeatures.contains(.fullVersion)
    }

    private func isEligible(forFeature feature: LocalProduct) -> Bool {
        #if os(iOS)
        return isFullVersion() || purchasedFeatures.contains(feature)
        #else
        return isFullVersion()
        #endif
    }

    public func isEligibleForFeedback() -> Bool {
        return isBeta || !purchasedFeatures.isEmpty
    }
    
    public func verifyEligible(forFeature feature: LocalProduct) throws {
        if isBeta {
            if cfg.isBetaFullVersion {
                return
            }
            guard !cfg.locksBetaFeatures else {
                throw ProductError.beta
            }
        }
        guard isEligible(forFeature: feature) else {
            throw ProductError.uneligible
        }
    }

    public func verifyEligible(forProvider metadata: Infrastructure.Metadata) throws {
        if isBeta {
            if cfg.isBetaFullVersion {
                return
            }
            guard !cfg.locksBetaFeatures else {
                throw ProductError.beta
            }
        }
        guard metadata.name != .oeck else {
            return
        }
        guard isEligible(forFeature: metadata.product) else {
            throw ProductError.uneligible
        }
    }

    public func hasPurchased(_ product: LocalProduct) -> Bool {
        return purchasedFeatures.contains(product)
    }

    public func isCancelledPurchase(_ product: LocalProduct) -> Bool {
        return cancelledPurchases.contains(product)
    }
    
    public func purchaseDate(forProduct product: LocalProduct) -> Date? {
        return purchaseDates[product]
    }

    public func reloadReceipt(andNotify: Bool = true) {
        guard let url = Bundle.main.appStoreReceiptURL else {
            log.warning("No App Store receipt found!")
            return
        }
        guard let receipt = Receipt(contentsOfURL: url) else {
            log.error("Could not parse App Store receipt!")
            return
        }

        if let originalAppVersion = receipt.originalAppVersion, let buildNumber = Int(originalAppVersion) {
            purchasedAppBuild = buildNumber
        }
        purchasedFeatures.removeAll()
        cancelledPurchases.removeAll()

        if let buildNumber = purchasedAppBuild {
            log.debug("Original purchased build: \(buildNumber)")

            // treat former purchases as full versions
            if buildNumber <= cfg.lastFullVersionBuild.0 {
                purchasedFeatures.insert(cfg.lastFullVersionBuild.1)
            }
        }
        if let iapReceipts = receipt.inAppPurchaseReceipts {
            purchaseDates.removeAll()
            
            log.debug("In-app receipts:")
            iapReceipts.forEach {
                guard let pid = $0.productIdentifier, let product = LocalProduct(rawValue: pid) else {
                    return
                }
                if let cancellationDate = $0.cancellationDate {
                    log.debug("\t\(pid) [cancelled on: \(cancellationDate)]")
                    cancelledPurchases.insert(product)
                    return
                }
                if let purchaseDate = $0.originalPurchaseDate {
                    log.debug("\t\(pid) [purchased on: \(purchaseDate)]")
                    purchaseDates[product] = purchaseDate
                }
                purchasedFeatures.insert(product)
            }
        }
        log.info("Purchased features: \(purchasedFeatures)")
        
        if andNotify {
            NotificationCenter.default.post(name: ProductManager.didReloadReceipt, object: nil)
        }
    }
}

extension ProductManager: SKPaymentTransactionObserver {
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadReceipt()
        }
    }
}

extension ProductManager: SKRequestDelegate {
    public func requestDidFinish(_ request: SKRequest) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadReceipt()
        }
        inApp.restorePurchases { [weak self] (finished, _, error) in
            guard finished else {
                return
            }
            DispatchQueue.main.async {
                self?.restoreCompletionHandler?(error)
                self?.restoreCompletionHandler = nil
            }
        }
    }
    
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.restoreCompletionHandler?(error)
            self?.restoreCompletionHandler = nil
        }
    }
}

extension ProductManager {
    public static let shared = ProductManager(
        Configuration(
            locksBetaFeatures: AppConstants.InApp.locksBetaFeatures,
            isBetaFullVersion: AppConstants.InApp.isBetaFullVersion,
            lastFullVersionBuild: AppConstants.InApp.lastFullVersionBuild
        )
    )

    public func reviewPurchases() {
        let service = TransientStore.shared.service
        reloadReceipt(andNotify: false)
        let isEligibleForFullVersion = isFullVersion()
        let hasCancelledFullVersion: Bool
        let hasCancelledTrustedNetworks: Bool
        var anyRefund = false
        
        #if os(iOS)
        hasCancelledFullVersion = !isEligibleForFullVersion && (isCancelledPurchase(.fullVersion) || isCancelledPurchase(.fullVersion_iOS))
        hasCancelledTrustedNetworks = !isEligibleForFullVersion && isCancelledPurchase(.trustedNetworks)
        #else
        hasCancelledFullVersion = !isEligibleForFullVersion && (isCancelledPurchase(.fullVersion) || isCancelledPurchase(.fullVersion_macOS))
        hasCancelledTrustedNetworks = false
        #endif
        
        // review features and potentially revert them if they were used (Siri is handled in AppDelegate)

        log.debug("Checking 'Trusted networks'")
        if hasCancelledFullVersion || hasCancelledTrustedNetworks {
            
            // reset trusted networks for ALL profiles (must load first)
            for key in service.allProfileKeys() {
                guard let profile = service.profile(withKey: key) else {
                    continue
                }
                #if os(iOS)
                if profile.trustedNetworks.includesMobile || !profile.trustedNetworks.includedWiFis.isEmpty {
                    profile.trustedNetworks.includesMobile = false
                    profile.trustedNetworks.includedWiFis.removeAll()
                    anyRefund = true
                }
                #else
                if !profile.trustedNetworks.includedWiFis.isEmpty {
                    profile.trustedNetworks.includedWiFis.removeAll()
                    anyRefund = true
                }
                #endif
            }
            if anyRefund {
                log.debug("\tRefunded")
            }
        }

        log.debug("Checking providers")
        for name in service.providerNames() {
            guard let metadata = InfrastructureFactory.shared.metadata(forName: name) else {
                continue
            }
            if hasCancelledFullVersion || (!isEligibleForFullVersion && isCancelledPurchase(metadata.product)) {
                service.removeProfile(ProfileKey(name))
                log.debug("\tRefunded provider: \(name)")
                anyRefund = true
            }
        }
        
        guard anyRefund else {
            return
        }

        //

        // save reverts and remove fraud VPN profile
        TransientStore.shared.serialize(withProfiles: true)
        VPN.shared.uninstall(completionHandler: nil)

        NotificationCenter.default.post(name: ProductManager.didReviewPurchases, object: nil)
    }
}
