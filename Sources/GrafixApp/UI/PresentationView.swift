import AppKit
import GrafixCore
import GrafixPort
import GrafixRender
import SwiftUI

/// Full-window slide show (Excalidraw+ presentation mode). Slides are rendered
/// letterboxed at screen pixel size; neighbours are pre-rendered for instant
/// navigation; transitions crossfade. Keys: arrows/space/page keys navigate,
/// Home/End jump, L toggles the laser, N the notes, Esc exits.
struct PresentationView: View {
  @Bindable var model: AppModel
  @State private var controller: PresentationController?
  @State private var controlsVisible = true
  @State private var hideTask: Task<Void, Never>?
  @State private var enteredFullScreen = false

  var body: some View {
    let doc = model.document
    let bg = Color(cgColor: CSSColor.cgColor(doc.scene.viewBackgroundColor, dark: true))
    ZStack {
      bg.ignoresSafeArea()
      if let c = controller {
        GeometryReader { geo in
          stage(c, size: geo.size, bg: bg)
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: "\(Int(geo.size.width))x\(Int(geo.size.height))") {
              try? await Task.sleep(for: .milliseconds(60))
              c.configure(size: geo.size, backing: NSApp.keyWindow?.backingScaleFactor ?? 2)
            }
        }
        .ignoresSafeArea()
      }
      PresentationKeys(onKey: handleKey).allowsHitTesting(false)
    }
    .onAppear { start() }
    .onDisappear { stop() }
    .onReceive(NotificationCenter.default.publisher(for: .grafixDebugKey)) { n in
      guard let c = controller, let code = n.object as? Int else { return }
      if code == 124 { c.next() } else if code == -1 { c.showNotes.toggle() }
    }
    .onChange(of: model.presenting) { _, p in if !p { stop() } }
  }

  // MARK: Stage

  private func stage(_ c: PresentationController, size: CGSize, bg: Color) -> some View {
    ZStack {
      if c.slides.isEmpty {
        Text("No slides. Add frames to the canvas to present them.")
          .font(.system(size: 18)).foregroundStyle(.secondary)
      } else if let img = c.images[c.shown] {
        let k = c.fit(c.shown, in: size)
        let r = c.slides[c.shown].bounds
        Image(decorative: img, scale: 1)
          .resizable().interpolation(.high)
          .frame(width: r.width * k, height: r.height * k)
          .id(c.shown)
          .transition(.opacity)
      }
      if c.laser { LaserLayer(controller: c) }
      if c.showNotes, let notes = c.current?.notes, !notes.isEmpty {
        VStack {
          Spacer()
          Text(notes)
            .font(.system(size: 16)).foregroundStyle(.white)
            .padding(14).frame(maxWidth: 560, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.7)))
            .padding(.bottom, 76)
        }
      }
      VStack {
        Spacer()
        controls(c).opacity(controlsVisible ? 1 : 0).allowsHitTesting(controlsVisible)
          .padding(.bottom, 20)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: c.shown)
    .contentShape(Rectangle())
    .onTapGesture { c.next() }
    .onContinuousHover { phase in
      if case .active(let p) = phase {
        wake()
        if c.laser { c.addTrailPoint(p) }
      }
    }
  }

  private func controls(_ c: PresentationController) -> some View {
    HStack(spacing: 4) {
      barButton("chevronleft", enabled: c.target > 0) { c.previous() }
      Text("\(c.target + 1) / \(max(c.count, 1))")
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .foregroundStyle(.white).frame(minWidth: 56)
      barButton("chevronright", enabled: c.target < c.count - 1) { c.next() }
      Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 18).padding(.horizontal, 4)
      barButton("laser", active: c.laser) { c.laser.toggle(); c.trail = [] }
      barButton("pencil", active: c.showNotes) { c.showNotes.toggle() }
      Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 18).padding(.horizontal, 4)
      barButton("cross") { model.presenting = false }
    }
    .padding(6)
    .background(Capsule().fill(.black.opacity(0.72)))
    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    .onHover { if $0 { wake() } }
  }

  private func barButton(_ icon: String, active: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      PortIconView(name: icon, size: 18, color: .white.opacity(enabled ? 1 : 0.35))
        .frame(width: 34, height: 34)
        .background(Circle().fill(active ? SlidesStyle.brand(false) : .clear))
    }
    .buttonStyle(.plain).disabled(!enabled)
  }

  // MARK: Lifecycle

  private func start() {
    let doc = model.document
    let c = PresentationController(scene: doc.scene, dark: true, start: model.presentingSlide)
    c.onChange = { model.presentingSlide = $0 }
    controller = c
    let headless = ProcessInfo.processInfo.environment["GRAFIX_SNAPSHOT"] != nil
    if !headless, let w = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible), !w.styleMask.contains(.fullScreen) {
      w.toggleFullScreen(nil)
      enteredFullScreen = true
    }
    wake()
  }

  private func stop() {
    hideTask?.cancel()
    NSCursor.setHiddenUntilMouseMoves(false)
    model.presentingSlide = 0
    model.presenting = false
    if enteredFullScreen {
      enteredFullScreen = false
      if let w = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible), w.styleMask.contains(.fullScreen) {
        w.toggleFullScreen(nil)
      }
    }
    controller = nil
  }

  private func wake() {
    controlsVisible = true
    hideTask?.cancel()
    hideTask = Task {
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
      NSCursor.setHiddenUntilMouseMoves(true)
    }
  }

  private func handleKey(_ e: NSEvent) -> Bool {
    guard let c = controller else { return false }
    switch e.keyCode {
    case 53: model.presenting = false
    case 124, 125, 49, 121, 36: c.next()
    case 123, 126, 116, 51: c.previous()
    case 115: c.go(to: 0)
    case 119: c.go(to: c.count - 1)
    default:
      switch e.charactersIgnoringModifiers?.lowercased() {
      case "l": c.laser.toggle(); c.trail = []
      case "n": c.showNotes.toggle()
      default: return false
      }
    }
    wake()
    return true
  }
}

/// Red laser pointer trail that fades over ~0.6s (Excalidraw's laser tool).
private struct LaserLayer: View {
  let controller: PresentationController

  var body: some View {
    TimelineView(.animation) { tl in
      Canvas { ctx, _ in
        let now = ProcessInfo.processInfo.systemUptime
        let pts = controller.trail.filter { now - $0.time < 0.6 }
        guard let last = pts.last else { return }
        for i in 1..<max(pts.count, 1) {
          let a = pts[i - 1], b = pts[i]
          let life = 1 - (now - b.time) / 0.6
          var p = Path()
          p.move(to: a.point)
          p.addLine(to: b.point)
          ctx.stroke(p, with: .color(.red.opacity(life)), style: StrokeStyle(lineWidth: 4 * life + 1, lineCap: .round))
        }
        let age = 1 - (now - last.time) / 0.6
        ctx.fill(
          Path(ellipseIn: CGRect(x: last.point.x - 6, y: last.point.y - 6, width: 12, height: 12)),
          with: .color(.red.opacity(max(0.2, age))))
        _ = tl.date
      }
    }
    .allowsHitTesting(false)
  }
}
