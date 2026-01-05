import SwiftUI

struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
            
            Text("100% Offline & Private")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            Capsule()
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PrivacyBadge_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyBadge()
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
