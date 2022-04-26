//
//  Profile+Extensions.swift
//  Passepartout
//
//  Created by Davide De Rosa on 3/13/22.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
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
import PassepartoutProviders
import PassepartoutUtils
import TunnelKitOpenVPN
import TunnelKitWireGuard

extension Profile {
    public var isProvider: Bool {
        return provider != nil
    }

    public var vpnProtocols: [VPNProtocolType] {
        if isProvider {
            return provider?.vpnProtocols ?? []
        } else {
            return host?.vpnProtocols ?? []
        }
    }
    
    public var requiresCredentials: Bool {
        if isProvider {
            return provider?.requiresCredentials(forProtocol: currentVPNProtocol) ?? false
        } else {
            return host?.requiresCredentials(forProtocol: currentVPNProtocol) ?? false
        }
    }
    
    public var account: Profile.Account {
        get {
            if isProvider {
                return providerAccount() ?? .init()
            } else {
                return hostAccount() ?? .init()
            }
        }
        set {
            if isProvider {
                setProviderAccount(newValue)
            } else {
                setHostAccount(newValue)
            }
        }
    }
}

extension Profile.Header {
    public func withNewId() -> Self {
        Profile.Header(
            uuid: .init(),
            name: name,
            providerName: providerName,
            lastUpdate: lastUpdate
        )
    }
    
    public func renamed(to newName: String) -> Self {
        var header = self
        header.name = newName
        return header
    }
    
    public func renamedUniquely(withLastUpdate: Bool) -> Self {
        let suffix: String
        if withLastUpdate, let lastUpdate = lastUpdate {
            suffix = lastUpdate.timestamp
        } else {
            guard let leadingUUID = id.uuidString.components(separatedBy: "-").first else {
                assertionFailure("UUID format?")
                return self
            }
            suffix = leadingUUID.lowercased()
        }
        let newName = "\(name).\(suffix)"
        return renamed(to: newName)
    }
}

extension Profile {
    public func withNewId() -> Self {
        var profile = self
        profile.header = profile.header.withNewId()
        return profile
    }

    public func renamed(to newName: String) -> Self {
        var profile = self
        profile.header = profile.header.renamed(to: newName)
        return profile
    }
    
    public func renamedUniquely(withLastUpdate: Bool) -> Self {
        var profile = self
        profile.header = profile.header.renamedUniquely(withLastUpdate: withLastUpdate)
        return profile
    }
}
