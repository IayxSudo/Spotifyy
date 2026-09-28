import SwiftUI

struct CommonIssuesTipView: View {
    var onDismiss: () -> Void
    
    var body: some View {
        Section {
            HStack(spacing: 15) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.title)
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 3) {
                    VStack(alignment: .leading) {
                        Text("common_issues_tip_title".localized)
                            .font(.headline)
                    }
                    
                    Link(
                        destination: URL(
                            string: "https://github.com/jaydenjcpy/SpotifyyReincarnated/blob/Master/common_issues.md"
                        )!,
                        label: {
                            VStack {
                                // `.primary` so the tip stays readable on the
                                // light themes.
                                Text("\("common_issues_tip_message".localized) ")
                                    .foregroundColor(.primary)
                                
                                + Text("common_issues_tip_button".localized)
                                    .foregroundColor(SpotifyySettingsView.spotifyAccentColor)
                                
                                + Text(".")
                                    .foregroundColor(.primary)
                            }
                            .font(.subheadline)
                        }
                    )
                }
                
                Spacer()
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(Color(UIColor.systemGray2))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 5)
        }
    }
}
