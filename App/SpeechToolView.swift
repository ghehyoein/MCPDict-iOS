import SwiftUI
import UniformTypeIdentifiers

struct SpeechToolView: View {
    @StateObject private var audio = SpeechSession()
    @State private var picking = false
    @State private var layers: Set<String> = ["頻譜", "基頻"]
    @State private var visible = 0.0...1.0
    @State private var previous = [ClosedRange<Double>]()
    @State private var selection: ClosedRange<Double>?
    @State private var frequency: Double?
    @State private var channelSheet = false
    private let options = ["頻譜", "基頻", "強度", "共振峰", "聲門脈衝"]
    var body: some View {
        content
            .navigationTitle(ui("語音分析")).navigationBarTitleDisplayMode(.inline)
            .toolbar { layerMenu }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { audio.choose(url) }
        }
        .onChange(of: audio.channels) { _, count in channelSheet = count > 1 }
        .confirmationDialog(ui("選擇聲道"), isPresented: $channelSheet) {
            ForEach(0..<audio.channels, id: \.self) { index in
                Button(index == 0 ? ui("左聲道") : index == 1 ? ui("右聲道") : String(index+1)) { audio.chooseChannel(index) }
            }
            Button(ui("取消"), role: .cancel) { audio.channels = 0 }
        }
        .onReceive(audio.$clip) { clip in
            if let clip { visible = 0...clip.duration; previous = []; selection = nil; frequency = nil }
        }
        .onDisappear { audio.close() }
        .alert(ui("提示"), isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) { Button(ui("好")) {} } message: { Text(audio.error ?? "") }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inputControls
                if let clip = audio.clip { clipControls(clip) }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var inputControls: some View {
                HStack {
                    Button(ui(audio.recording ? "停止錄音" : "開始錄音")) {
                        if audio.recording { audio.stopRecording() } else { Task { await audio.record() } }
                    }.disabled(audio.busy || audio.permissionPending)
                    Button(ui(audio.busy ? "取消導入" : "導入音頻")) {
                        if audio.busy { audio.cancel() } else { picking = true }
                    }.disabled(audio.recording || audio.permissionPending)
                    if audio.busy { ProgressView() }
                }.buttonStyle(.bordered)
                if audio.recording {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text(ui("錄音中") + String(format: " %.1f s", audio.elapsed)).monospacedDigit()
                    }
                }
    }
    private var layerMenu: some View {
        Menu {
            ForEach(options, id: \.self) { key in
                Toggle(ui(key), isOn: Binding<Bool>(get: { layers.contains(key) }, set: { enabled in
                    if enabled { layers.insert(key) } else { layers.remove(key) }
                }))
            }
        } label: { Image(systemName: "slider.horizontal.3") }
    }
    @ViewBuilder private func clipControls(_ clip: SpeechClip) -> some View {
                    HStack {
                        Button(ui(audio.playing ? "停止播放" : "播放")) {
                            if audio.playing { audio.stopPlayback() } else { audio.play(nil) }
                        }
                        Button(ui("播放選區")) { audio.play(selection) }.disabled((selection?.span ?? 0) <= 0)
                    }.disabled(audio.recording || audio.busy).buttonStyle(.bordered)
                    Text(ui("波形")).font(.caption)
                    plot(clip).frame(height: 300)
                    Text(ui("頻譜") + " 0–5000 Hz  ·  " + ui("基頻") + " 55–550 Hz").font(.caption)
                    if let selection {
                        let frame = clip.frames[min(clip.frames.count-1, Int(selection.lowerBound*16000)/256)]
                        Text(String(format: "%.3f–%.3f s", selection.lowerBound, selection.upperBound)
                             + (frequency.map { String(format: " · %.0f Hz", $0) } ?? "")
                             + (frame.pitch.isFinite ? String(format: " · F0 %.1f Hz", frame.pitch) : "")
                             + (frame.intensity.isFinite ? String(format: " · %.1f dB", frame.intensity) : ""))
                            .font(.caption).monospacedDigit()
                    }
                    HStack {
                        Button(ui("全段")) { zoom(0...clip.duration, clip) }
                        Button { magnify(2, clip) } label: { Image(systemName: "plus.magnifyingglass") }
                        Button { magnify(0.5, clip) } label: { Image(systemName: "minus.magnifyingglass") }
                        Button(ui("選區")) { if let selection { zoom(selection, clip) } }.disabled((selection?.span ?? 0) <= 0)
                        Button { if let last = previous.popLast() { visible = last } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(previous.isEmpty)
                    }.buttonStyle(.bordered)
                    if clip.duration > visible.span {
                        Slider(value: Binding(get: { visible.lowerBound }, set: { start in visible = start...(start+visible.span) }),
                               in: 0...max(0.000001, clip.duration-visible.span)).accessibilityLabel(ui("時間位置"))
                    }
                    Text(String(format: "%.3f–%.3f / %.2f s", visible.lowerBound, visible.upperBound, clip.duration)).font(.caption)
                    if clip.limited { Text(ui("僅分析前120秒")).font(.caption) }
    }
    private func zoom(_ target: ClosedRange<Double>, _ clip: SpeechClip) {
        let width = min(clip.duration, max(0.008, target.span))
        let start = max(0, min(clip.duration-width, (target.upperBound+target.lowerBound-width)/2))
        let next = start...min(clip.duration, start+width)
        if visible != next { previous.append(visible); visible = next }
    }
    private func magnify(_ factor: Double, _ clip: SpeechClip) {
        let center = (visible.lowerBound+visible.upperBound)/2, half = visible.span/(2*factor)
        zoom((center-half)...(center+half), clip)
    }
    private func plot(_ clip: SpeechClip) -> some View {
        GeometryReader { geometry in
            Canvas { ctx, size in
                let w = Double(size.width), h = Double(size.height), split = h*0.30, lower = h-split
                guard visible.span > 0, w > 0 else { return }
                func x(_ t: Double) -> Double { (t-visible.lowerBound)/visible.span*w }
                func stroke(_ path: Path, _ color: Color, _ width: CGFloat = 1) { ctx.stroke(path, with: .color(color), lineWidth: width) }
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                if layers.contains("頻譜") {
                    let left = max(0, floor(visible.lowerBound*250)), right = min(Double(clip.spectrum.width), ceil(visible.upperBound*250))
                    if let crop = clip.spectrum.cropping(to: CGRect(x: left, y: 0, width: max(1,right-left), height: 161)) {
                        ctx.draw(Image(decorative: crop, scale: 1), in: CGRect(x: x(left/250), y: split, width: max(1,(right-left)/250/visible.span*w), height: lower))
                    }
                }
                let first = min(clip.frames.count-1, Int(visible.lowerBound*62.5)), last = min(clip.frames.count, Int(ceil(visible.upperBound*62.5)))
                var wave = Path(), pitch = Path(), intensity = Path(), pulses = Path(), formants = Path()
                var lastPitch = false, lastIntensity = false
                for index in first..<max(first,last) {
                    let f = clip.frames[index], px = x(Double(index)*0.016)
                    wave.move(to: CGPoint(x: px, y: split*(1-Double(f.high))/2)); wave.addLine(to: CGPoint(x: px, y: split*(1-Double(f.low))/2))
                    if f.pitch.isFinite {
                        let pt = CGPoint(x: px, y: h-lower*(Double(f.pitch)-55)/495)
                        if lastPitch { pitch.addLine(to: pt) } else { pitch.move(to: pt) }
                    }
                    lastPitch = f.pitch.isFinite
                    if f.intensity.isFinite {
                        let pt = CGPoint(x: px, y: h-lower*min(1,max(0,(Double(f.intensity)-20)/80)))
                        if lastIntensity { intensity.addLine(to: pt) } else { intensity.move(to: pt) }
                    }
                    lastIntensity = f.intensity.isFinite
                    if layers.contains("共振峰") { for hz in f.formants { formants.addEllipse(in: CGRect(x: px, y: h-lower*Double(hz)/5000, width: 2, height: 2)) } }
                    if layers.contains("聲門脈衝") { for p in f.pulses { let t=x(Double(p)/16000); pulses.move(to: CGPoint(x:t,y:0)); pulses.addLine(to:CGPoint(x:t,y:split*0.18)) } }
                }
                if visible.span < 1 {
                    wave = Path()
                    let lo = Int(visible.lowerBound*16000), hi = min(clip.samples.count, Int(ceil(visible.upperBound*16000)))
                    for i in lo..<max(lo,hi) {
                        let p = CGPoint(x:x(Double(i)/16000),y:split*(1-Double(clip.samples[i]))/2)
                        if i == lo { wave.move(to:p) } else { wave.addLine(to:p) }
                    }
                }
                stroke(wave, .black); stroke(pulses,.purple)
                if layers.contains("基頻") { stroke(pitch,.blue,2) }
                if layers.contains("強度") { stroke(intensity,.green,2) }
                ctx.fill(formants,with:.color(.red))
                if let selection {
                    let rect = CGRect(x:x(selection.lowerBound),y:0,width:max(1,selection.span/visible.span*w),height:h)
                    ctx.fill(Path(rect),with:.color(.orange.opacity(0.28)))
                }
            }.clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                func time(_ px: CGFloat) -> Double { visible.lowerBound + max(0,min(1,Double(px)/max(1,Double(geometry.size.width))))*visible.span }
                let a = time(event.startLocation.x), b = time(event.location.x)
                selection = min(a,b)...max(a,b)
                let fraction = Double(event.location.y)/max(1,Double(geometry.size.height))
                frequency = fraction >= 0.3 ? min(5000,max(0,(1-fraction)/0.7*5000)) : nil
            })
            .simultaneousGesture(MagnificationGesture().onEnded { magnify($0,clip) })
        }
    }
}
private extension ClosedRange where Bound == Double { var span: Double { upperBound-lowerBound } }
