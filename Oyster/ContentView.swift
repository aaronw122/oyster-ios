import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Oyster")
                .font(.largeTitle.bold())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
