import SwiftUI

struct NavigationSectionView: View {
    var color: Color
    var title: String
    var imageSystemName: String
    
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .foregroundColor(color)
                
                Image(systemName: imageSystemName)
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
            }
            .frame(width: 30, height: 30)
            
            // `.primary` rather than white: the light themes (Light mode, Pink
            // Light, a light custom theme) draw these rows on a light
            // background, where white text would disappear.
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            ChevronRightView()
        }
    }
}
