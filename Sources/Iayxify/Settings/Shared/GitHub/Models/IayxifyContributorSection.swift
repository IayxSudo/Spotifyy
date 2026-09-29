struct IayxifyContributorSection: Decodable, Equatable {
    var title: String
    var shuffled: Bool
    var contributors: [IayxifyContributor]
}
