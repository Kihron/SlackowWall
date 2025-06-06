//
//  ProfileSection.swift
//  SlackowWall
//
//  Created by Kihron on 5/3/25.
//

import DefaultCodable
import SwiftUI

extension Preferences {
    @DefaultCodable
    struct ProfileSection: Codable, Hashable {
        var id: UUID = UUID()
        var name: String = "Main"
        var expectedMWidth: Int? = nil
        var expectedMHeight: Int? = nil

        init() {}
    }
}
