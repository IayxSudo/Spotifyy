import Foundation

/// Name shown by Spotify for the patched plan and its badge.
///
/// Iayxify's own copy, and the only string the animated rainbow looks for on
/// Spotify's "Your Premium" page (`IayxifyRainbow.brandName`), so the two must
/// stay in sync.
private let iayxifyPlanName = "Iayxify"

/// One solid colour has to go into the protobuf, so the payload carries the
/// rainbow's first hue. Where Spotify renders the name as a plain label, the
/// animated gradient paints over it at runtime.
private var iayxifyPlanColor: String { SpotifyyAppearance.planAccentHex }

func getPremiumPlanBadge() throws -> Data {
    let badge = YourPremiumBadge.with {
        $0.name = iayxifyPlanName
        $0.version = 2
        $0.colorCode = iayxifyPlanColor
    }
    
    return try badge.serializedData()
}

func getPremiumPlanRowData(originalPremiumPlanRow: PremiumPlanRow) throws -> Data {
    var premiumPlanRow = originalPremiumPlanRow
    
    premiumPlanRow.planName = iayxifyPlanName
    premiumPlanRow.planIdentifier = iayxifyPlanName
    premiumPlanRow.colorCode = iayxifyPlanColor
    
    return try premiumPlanRow.serializedData()
}

func getPlanOverviewData() throws -> Data {
    let plan = SpotifyPlan.with {
        $0.notice = SpotifyPlan.Notice.with {
            $0.message = "payment_notice".localized
            $0.status = 2 // 0 - trial, 1 - prepaid, 2 - subsсription
        }
        $0.subscription = SpotifyPlan.SubscriptionInfo.with {
            $0.planVariant = 2
            $0.planName = iayxifyPlanName
            $0.planCategory = iayxifyPlanName
            $0.colorCode = iayxifyPlanColor
            $0.features = [
                SpotifyPlan.Feature.with {
                    $0.color = SpotifyyAppearance.spotifyGreenHex
                    $0.description_p = "ad_free_music_listening".localized
                    $0.icon = SpotifyPlan.IconType.check
                },
                SpotifyPlan.Feature.with {
                    $0.color = SpotifyyAppearance.spotifyGreenHex
                    $0.description_p = "play_songs_in_any_order".localized
                    $0.icon = SpotifyPlan.IconType.check
                },
                SpotifyPlan.Feature.with {
                    $0.color = SpotifyyAppearance.spotifyGreenHex
                    $0.description_p = "organize_listening_queue".localized
                    $0.icon = SpotifyPlan.IconType.check
                }
            ]
        }
    }
    
    return try plan.serializedData()
}
