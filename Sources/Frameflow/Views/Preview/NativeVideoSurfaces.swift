import AVKit
import SwiftUI

struct NativeVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let fillsFrame: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = videoGravity
    }

    private var videoGravity: AVLayerVideoGravity {
        fillsFrame ? .resizeAspectFill : .resizeAspect
    }
}

struct ZoomableNativeVideoSurface: View {
    let player: AVPlayer
    let zoomMultiplier: Double
    let fillsFrame: Bool

    var body: some View {
        GeometryReader { geometry in
            NativeVideoSurface(player: player, fillsFrame: fillsFrame)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(CGFloat(max(0.08, zoomMultiplier)), anchor: .center)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .background(Color.black)
        .clipped()
    }
}
