//
//  DeviceStatus.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation

struct DeviceStatus: Codable {
    struct Battery: Codable {
        var level: Int
        var isCharging: Bool
    }

    struct Music: Codable {
        var isPlaying: Bool
        var title: String
        var artist: String
        var volume: Int
        var isMuted: Bool
        var albumArt: String
        var likeStatus: String
    }

    var battery: Battery
    var isPaired: Bool
    var music: Music?
}
