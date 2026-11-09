import SwiftUI
import ServiceManagement

// MARK: - Sprite preview (AppKit view hosted in SwiftUI)

final class SpritePreviewNSView: NSView {
    var visual: Visual = .stand { didSet { needsDisplay = true } }
    var tint = "auto" { didSet { needsDisplay = true } }
    var skin: Skin? { didSet { needsDisplay = true } }
    var scale: CGFloat = 5 { didSet { needsDisplay = true } }
    private var t = Double.random(in: 0..<10)
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.t += 1.0 / 12.0
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let ox = ((bounds.width - CGFloat(canvasW) * scale) / 2).rounded()
        let oy = ((bounds.height - CGFloat(canvasH) * scale) / 2).rounded()
        drawSprite(ctx: ctx, scale: scale, origin: CGPoint(x: ox, y: oy), visual: visual, t: t, dir: 1, vy: 1,
                   palette: Palette.make(tint: tint, variant: 0, skin: skin ?? .current))
    }
}

struct SpritePreview: NSViewRepresentable {
    var visual: Visual
    var tint: String = "auto"
    var skin: Skin? = nil
    var scale: CGFloat = 5
    func makeNSView(context: Context) -> SpritePreviewNSView { SpritePreviewNSView(frame: .zero) }
    func updateNSView(_ v: SpritePreviewNSView, context: Context) {
        v.visual = visual; v.tint = tint; v.skin = skin; v.scale = scale
    }
}

// MARK: - Small state helpers (no @State: its macro plugin isn't available with Command Line Tools only)

final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

/// Wires `AgentPet --statusline` into Claude Code's settings so plan-usage percentages reach the pets.
final class LimitsLink: ObservableObject {
    @Published var message: String?
    @Published var linked = LimitsLink.isLinked()

    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }

    static func isLinked() -> Bool {
        guard let d = try? Data(contentsOf: settingsURL), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let sl = o["statusLine"] as? [String: Any], let c = sl["command"] as? String else { return false }
        return c.contains("--statusline")
    }

    func connect() {
        guard let exe = Bundle.main.executablePath else { return }
        var o: [String: Any] = [:]
        if let d = try? Data(contentsOf: Self.settingsURL) {
            guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                message = "No pude leer ~/.claude/settings.json; no lo he tocado."; return
            }
            o = j
        }
        if o["statusLine"] != nil, !Self.isLinked() {
            message = "Ya tienes una línea de estado configurada y no la he sustituido. Añade a mano: \(exe) --statusline"
            return
        }
        o["statusLine"] = ["type": "command", "command": "\"\(exe)\" --statusline"]
        do {
            try? FileManager.default.createDirectory(at: Self.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let d = try JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try d.write(to: Self.settingsURL, options: .atomic)
            linked = true
            message = "Listo. Se verá en cuanto Claude Code muestre su próxima línea de estado."
        } catch { message = "No se pudo guardar: \(error.localizedDescription)" }
    }
}

final class LoginModel: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var error: String?
    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "No se pudo cambiar (¿ejecutas la app desde su .app?): \(error.localizedDescription)"
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Building blocks

private enum Page: Int, CaseIterable, Identifiable {
    case pet, behavior, bubbles, agents, general
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .pet: return "Mascota"
        case .behavior: return "Comportamiento"
        case .bubbles: return "Burbujas"
        case .agents: return "Agentes"
        case .general: return "General"
        }
    }
    var subtitle: String {
        switch self {
        case .pet: return "Elige quién te acompaña y cómo se ve."
        case .behavior: return "Cómo se mueve por tu escritorio."
        case .bubbles: return "El texto que muestra sobre su cabeza."
        case .agents: return "De dónde saca lo que están haciendo tus IAs."
        case .general: return "Sistema y datos de la app."
        }
    }
    var icon: String {
        switch self {
        case .pet: return "pawprint.fill"
        case .behavior: return "figure.walk"
        case .bubbles: return "text.bubble.fill"
        case .agents: return "cpu.fill"
        case .general: return "gearshape.fill"
        }
    }
    var color: Color {
        switch self {
        case .pet: return .orange
        case .behavior: return .green
        case .bubbles: return .blue
        case .agents: return .purple
        case .general: return .gray
        }
    }
}

private struct Card<Content: View>: View {
    let title: String?
    let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: Trailing
    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 9)
    }
}

private struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var disabled = false
    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, disabled: Bool = false) {
        self.title = title; self.subtitle = subtitle; self._isOn = isOn; self.disabled = disabled
    }
    var body: some View {
        Row(title, subtitle: subtitle) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

private struct SliderRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String
    var disabled = false

    var body: some View {
        Row(title, subtitle: subtitle) {
            HStack(spacing: 10) {
                Group {
                    if let step { Slider(value: $value, in: range, step: step) }
                    else { Slider(value: $value, in: range) }
                }
                .frame(width: 170)
                Text(format(value))
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

private struct PageHeader: View {
    let page: Page
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(page.title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Root

struct SettingsView: View {
    @StateObject private var selection = Box<Page>(.pet)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(page: selection.value)
                    switch selection.value {
                    case .pet: PetPage()
                    case .behavior: BehaviorPage()
                    case .bubbles: BubblesPage()
                    case .agents: AgentsPage()
                    case .general: GeneralPage()
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 34)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 800, height: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SpritePreview(visual: .hop, tint: "auto", skin: .claude, scale: 1.5)
                    .frame(width: 40, height: 34)
                Text("AgentPet").font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .padding(.leading, 6)
            .padding(.top, 30)
            .padding(.bottom, 14)

            ForEach(Page.allCases) { page in
                let selected = selection.value == page
                Button { selection.value = page } label: {
                    HStack(spacing: 9) {
                        Image(systemName: page.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.color.gradient))
                        Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? Color.primary.opacity(0.10) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("v0.1").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 200)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
    }
}

// MARK: - Pages

private struct PetPage: View {
    @AppStorage("tint") private var tint = "auto"
    @AppStorage("skin") private var skin = "claude"
    @AppStorage("scale") private var scale = 4.0
    @AppStorage("variants") private var variants = true
    @AppStorage("borders") private var borders = true
    @StateObject private var previewBox = Box<Visual>(.coding)

    private let previewStates: [Visual] = [.stand, .walk, .hop, .sleep, .thinking, .coding, .running, .reading, .searching, .planning, .delegating, .responding, .waiting, .done, .error]

    var body: some View {
        Card("Vista previa") {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color.orange.opacity(0.10), Color.purple.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 2).padding(.horizontal, 20).padding(.bottom, 31)
                    SpritePreview(visual: previewBox.value, tint: tint, skin: Skin(rawValue: skin), scale: 6)
                        .id(skin)
                    Text(previewBox.value.label)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: 0)
                        .opacity(0)
                }
                .frame(height: 190)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(previewStates, id: \.self) { v in
                            let on = previewBox.value == v
                            Button { previewBox.value = v } label: {
                                Text(v.label)
                                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                                    .foregroundStyle(on ? Color.white : Color.primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .padding(.vertical, 10)
        }

        Card("Personaje") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Skin.allCases, id: \.rawValue) { s in
                    let on = skin == s.rawValue
                    Button { skin = s.rawValue } label: {
                        VStack(spacing: 2) {
                            SpritePreview(visual: .stand, tint: "auto", skin: s, scale: 3)
                                .frame(height: 70)
                            Text(s.name).font(.system(size: 11, weight: on ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Color.accentColor : Color.clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
        }

        Card("Aspecto") {
            Row("Color", subtitle: "«A» es el color natural del personaje.") {
                HStack(spacing: 7) {
                    swatch(id: "auto", color: Color(nsColor: NSColor(cgColor: hex(Skin(rawValue: skin)?.natural.0 ?? 0xD97757)) ?? .orange), label: "A", help: "Color natural")
                    ForEach(Palette.tints, id: \.id) { t in
                        swatch(id: t.id, color: Color(nsColor: NSColor(cgColor: hex(t.body)) ?? .orange), label: nil, help: t.name)
                    }
                }
            }
            Divider()
            ToggleRow("Bordes", subtitle: "Contorno oscuro en la mascota y en el cuadro de texto. Sin bordes se ven más suaves.", isOn: $borders)
            Divider()
            ToggleRow("Un color distinto por agente", subtitle: "Así distingues de un vistazo qué mascota es de cada proyecto.", isOn: $variants)
            Divider()
            SliderRow(title: "Tamaño", subtitle: nil, value: $scale, range: 2...8, step: 1, format: { "×\(Int($0))" })
        }
    }

    private func swatch(id: String, color: Color, label: String?, help: String) -> some View {
        let on = tint == id
        return Button { tint = id } label: {
            Circle().fill(color)
                .frame(width: 22, height: 22)
                .overlay(Group { if let label { Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.55)) } })
                .overlay(Circle().stroke(Color.primary.opacity(on ? 0.85 : 0.12), lineWidth: on ? 2.5 : 1))
                .padding(2)
        }.buttonStyle(.plain).help(help)
    }
}

private struct BehaviorPage: View {
    @AppStorage("speed") private var speed = 1.0
    @AppStorage("energy") private var energy = 1.0
    @AppStorage("gravity") private var gravity = 1.0
    @AppStorage("useWindows") private var useWindows = true
    @AppStorage("jumpWindows") private var jumpWindows = true
    @AppStorage("sleepy") private var sleepy = true
    @AppStorage("social") private var social = true
    @AppStorage("alwaysShow") private var alwaysShow = true
    @AppStorage("maxPets") private var maxPets = 6
    @AppStorage("hideIdle") private var hideIdle = 20.0

    var body: some View {
        Card("Movimiento") {
            SliderRow(title: "Velocidad al caminar", value: $speed, range: 0.3...3, step: nil, format: { String(format: "%.1f×", $0) })
            Divider()
            SliderRow(title: "Energía", subtitle: "Cuánto se mueve y salta.", value: $energy, range: 0.3...3, step: nil, format: { String(format: "%.1f×", $0) })
            Divider()
            SliderRow(title: "Gravedad", value: $gravity, range: 0.4...2.5, step: nil, format: { String(format: "%.1f×", $0) })
        }
        Card("Escritorio") {
            ToggleRow("Subirse a las ventanas", subtitle: "Camina por el borde superior de las ventanas visibles.", isOn: $useWindows)
            Divider()
            ToggleRow("Saltar entre ventanas y al suelo", isOn: $jumpWindows, disabled: !useWindows)
            Divider()
            ToggleRow("Echarse a dormir de vez en cuando", isOn: $sleepy)
            Divider()
            ToggleRow("Interactuar entre ellas", subtitle: "Las mascotas sin tarea se saludan, juegan, se persiguen o duermen juntas.", isOn: $social)
            Divider()
            ToggleRow("Mostrar una mascota sin agentes", subtitle: "Si lo apagas, el escritorio queda limpio cuando no hay nadie trabajando.", isOn: $alwaysShow)
        }
        Card("Con varios agentes") {
            SliderRow(title: "Despedir agentes inactivos", subtitle: "Tras este tiempo sin actividad, su mascota se va con un «puf».",
                      value: $hideIdle, range: 0...120, step: 5, format: { $0 == 0 ? "nunca" : "\(Int($0)) s" })
            Divider()
            Row("Máximo de mascotas a la vez") {
                Stepper(value: $maxPets, in: 1...12) { Text("\(maxPets)").font(.system(size: 13, weight: .medium).monospacedDigit()) }
                    .fixedSize()
            }
        }
        Text("Puedes agarrar y lanzar a cualquier mascota con el ratón. Un clic la hace saltar y el clic derecho abre su menú.")
            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 6)
    }
}

private struct BubblesPage: View {
    @AppStorage("bubbles") private var bubbles = true
    @AppStorage("bubbleProject") private var project = true
    @AppStorage("bubbleFont") private var font = 12.0
    @AppStorage("idleBubble") private var idle = true
    @AppStorage("usage") private var usage = true
    @AppStorage("usageDelta") private var usageDelta = 5.0
    @StateObject private var link = LimitsLink()

    var body: some View {
        Card("Límites de uso") {
            ToggleRow("Mostrar el uso del plan", subtitle: "Dos barritas dentro de la burbuja (sesión de 5 h y semana). Aparecen unos segundos cuando un agente termina o cuando el porcentaje cambia.", isOn: $usage)
            Divider()
            SliderRow(title: "Mostrar al cambiar", value: $usageDelta, range: 1...20, step: 1, format: { "\(Int($0)) %" }, disabled: !usage)
            Divider()
            Row("Claude Code", subtitle: link.message ?? (link.linked ? "Conectado: Claude Code envía sus límites a AgentPet." : "Claude Code solo entrega estos datos a su línea de estado. Conéctala para que lleguen aquí (edita ~/.claude/settings.json).")) {
                Button(link.linked ? "Reconectar" : "Conectar") { link.connect() }
            }
            .opacity(usage ? 1 : 0.45).disabled(!usage)
        }
        Card("Texto sobre la mascota") {
            ToggleRow("Mostrar lo que hace cada agente", subtitle: "Por ejemplo «Editando Router.swift» o «Ejecutando: npm test».", isOn: $bubbles)
            Divider()
            ToggleRow("Incluir el nombre del proyecto", isOn: $project, disabled: !bubbles)
            Divider()
            ToggleRow("Avisar cuando un agente espera órdenes", isOn: $idle, disabled: !bubbles)
            Divider()
            SliderRow(title: "Tamaño de letra", value: $font, range: 9...18, step: 1, format: { "\(Int($0)) pt" }, disabled: !bubbles)
        }
        Card("Así se verá") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["Editando Router.swift", "Ejecutando: npm test", "Necesita tu permiso: Bash", "Buscando “handleLogin”"], id: \.self) { t in
                    Text(t)
                        .font(.system(size: font, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(red: 1, green: 0.97, blue: 0.94)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(red: 0.165, green: 0.106, blue: 0.082), lineWidth: 2))
                        .foregroundStyle(Color(red: 0.165, green: 0.106, blue: 0.082))
                }
            }
            .padding(.vertical, 12)
            .opacity(bubbles ? 1 : 0.4)
        }
    }
}

private struct AgentsPage: View {
    @ObservedObject var manager = PetManager.shared
    @AppStorage("claudeEnabled") private var claude = true
    @AppStorage("claudeChat") private var chat = false
    @AppStorage("pollSeconds") private var poll = 3.0
    @AppStorage("demo") private var demo = false
    @AppStorage("demoCount") private var demoCount = 3

    var body: some View {
        Card("Fuentes") {
            ToggleRow("Claude Code", subtitle: "Terminal y app de escritorio.", isOn: $claude)
            Divider()
            ToggleRow("Claude chat (app de escritorio)", subtitle: "Experimental: detecta cuándo la app está recibiendo una respuesta mirando su tráfico de red. No sabe de qué trata, solo si está pensando o respondiendo.", isOn: $chat, disabled: !claude)
            Divider()
            Row("Codex, Gemini CLI, Cursor…") {
                Text("Próximamente").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Divider()
            SliderRow(title: "Consultar cada", value: $poll, range: 0.5...5, step: 0.5, format: { String(format: "%.1f s", $0) })
        }

        Card("Detectados ahora") {
            if manager.agents.isEmpty {
                Row("Ninguno", subtitle: "Abre `claude` en una terminal y aparecerá aquí.") { EmptyView() }
            }
            ForEach(Array(manager.agents.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Divider() }
                Row(a.label, subtitle: a.text) {
                    Text(a.state.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(a.state == .waiting ? Color.orange.opacity(0.25) : Color.primary.opacity(0.08)))
                }
            }
        }

        Card("Modo demo") {
            ToggleRow("Simular agentes", subtitle: "Para probar las animaciones sin tener nada en marcha.", isOn: $demo)
            Divider()
            Row("Agentes simulados") {
                Stepper(value: $demoCount, in: 1...8) { Text("\(demoCount)").font(.system(size: 13, weight: .medium).monospacedDigit()) }
                    .fixedSize()
            }
            .opacity(demo ? 1 : 0.45).disabled(!demo)
        }
    }
}

private struct GeneralPage: View {
    @AppStorage("dockIcon") private var dockIcon = false
    @AppStorage("saver") private var saver = "auto"
    @StateObject private var login = LoginModel()

    var body: some View {
        Card("Energía") {
            Row("Modo ahorro", subtitle: "Las mascotas dejan de pasear y se echan a dormir, y la app consulta todo con menos frecuencia. Los agentes que trabajan siguen animados. «Automático» se activa con batería o modo de bajo consumo.") {
                Picker("", selection: $saver) {
                    Text("Automático").tag("auto")
                    Text("Siempre").tag("always")
                    Text("Nunca").tag("off")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
        }
        Card("Sistema") {
            ToggleRow("Abrir al iniciar sesión", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
            if let e = login.error {
                Text(e).font(.system(size: 11)).foregroundStyle(.red).padding(.bottom, 8)
            }
            Divider()
            ToggleRow("Mostrar icono en el Dock", subtitle: "Siempre tienes el icono de la barra de menús.", isOn: $dockIcon)
        }
        Card("Acerca de") {
            HStack(spacing: 16) {
                SpritePreview(visual: .hop, tint: "auto", skin: .claude, scale: 4)
                    .frame(width: 100, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AgentPet").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Versión 0.1").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Una mascota de escritorio para tus agentes de código.").font(.system(size: 12))
                }
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }
}
