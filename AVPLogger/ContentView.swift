import SwiftUI

struct ContentView: View {
    @State private var console = SpatialConsoleLogger(tag: "DEMO")

    var body: some View {
        VStack(spacing: 24) {
            Text("AVPLogger")
                .font(.largeTitle.weight(.semibold))

            HStack(spacing: 16) {
                Button("Tagged Log") {
                    console.log("The spatial console receives this line.")
                }
                .buttonStyle(.borderedProminent)

                Button("Untagged Print") {
                    print("This untagged line stays in Xcode's console.")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(48)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
