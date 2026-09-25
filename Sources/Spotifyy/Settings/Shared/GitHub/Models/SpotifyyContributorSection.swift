struct SpotifyyContributorSection: Decodable, Equatable {
    var title: String
    var shuffled: Bool
    var contributors: [SpotifyyContributor]
}
