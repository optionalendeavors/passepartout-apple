//
//  WizardProviderViewController.swift
//  Passepartout-iOS
//
//  Created by Davide De Rosa on 9/4/18.
//  Copyright (c) 2019 Davide De Rosa. All rights reserved.
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

import UIKit
import PassepartoutCore
import Convenience
import SwiftyBeaver

private let log = SwiftyBeaver.self

class WizardProviderViewController: UITableViewController, StrongTableHost {
    private var available: [Infrastructure.Metadata] = []
    
    private var createdProfile: ProviderConnectionProfile?
    
    // MARK: StrongTableHost
    
    let model = StrongTableModel<SectionType, RowType>()
    
    func reloadModel() {
        available = TransientStore.shared.service.availableProviders()

        model.clear()
        model.add(.availableProviders)
        model.add(.listActions)
        model.set(.provider, count: available.count, forSection: .availableProviders)
        model.set([.updateList], forSection: .listActions)
    }
    
    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.Core.Organizer.Sections.Providers.header
        reloadModel()
    }
    
    private func next(withMetadata metadata: Infrastructure.Metadata) {
        guard ProductManager.shared.isEligible(forProvider: metadata.name) else {
            presentPurchaseScreen(forProduct: metadata.product)
            return
        }

        let profile = ProviderConnectionProfile(name: metadata.name)
        createdProfile = profile
        
        let accountVC = StoryboardScene.Main.accountIdentifier.instantiate()
        let infrastructure = InfrastructureFactory.shared.infrastructure(forName: metadata.name)
        accountVC.usernamePlaceholder = infrastructure.defaults.username
        accountVC.infrastructureName = infrastructure.name
        accountVC.delegate = self
        navigationController?.pushViewController(accountVC, animated: true)
    }

    private func finish(withCredentials credentials: Credentials) {
        guard let profile = createdProfile else {
            fatalError("No profile created?")
        }
        let service = TransientStore.shared.service
        dismiss(animated: true) {
            service.addOrReplaceProfile(profile, credentials: credentials)
        }
    }
    
    private func updateProvidersList() {
        let hud = HUD(view: view)
        InfrastructureFactory.shared.updateIndex { [weak self] in
            if let error = $0 {
                hud.hide()
                log.error("Unable to update providers list: \(error)")
                return
            }

            ProductManager.shared.listProducts { (products, error) in
                hud.hide()
                if let error = error {
                    log.error("Unable to list products: \(error)")
                    return
                }
                self?.reloadModel()
                self?.tableView.reloadData()
            }
        }
    }

    @IBAction private func close() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: -

extension WizardProviderViewController {
    enum SectionType {
        case availableProviders
        
        case listActions
    }
    
    enum RowType {
        case provider
        
        case updateList
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return model.numberOfSections
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.numberOfRows(forSection: section)
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = model.row(at: indexPath)
        let cell = Cells.setting.dequeue(from: tableView, for: indexPath)
        switch row {
        case .provider:
            let metadata = available[indexPath.row]
            cell.apply(.current)
            cell.imageView?.image = metadata.logo
            cell.leftText = metadata.description
            
        case .updateList:
            cell.applyAction(.current)
            cell.imageView?.image = nil
            cell.leftText = L10n.Core.Wizards.Provider.Cells.UpdateList.caption
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = model.row(at: indexPath)
        switch row {
        case .provider:
            let metadata = available[indexPath.row]
            next(withMetadata: metadata)
        
        case .updateList:
            tableView.deselectRow(at: indexPath, animated: true)
            updateProvidersList()
        }
    }
}

// MARK: -

extension WizardProviderViewController: AccountViewControllerDelegate {
    func accountController(_: AccountViewController, didEnterCredentials credentials: Credentials) {
    }
    
    func accountControllerDidComplete(_ vc: AccountViewController) {
        finish(withCredentials: vc.credentials)
    }
}
