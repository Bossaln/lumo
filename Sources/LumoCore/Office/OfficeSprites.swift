import Foundation

/// Haltung einer Figur.
public enum OfficePose: Equatable, Sendable {
    case stand
    case walk(frame: Int)
    case sitDesk(typing: Bool)
    case sitCouch(drinking: Bool)
    case lie
}

/// Haar- und Hautton einer Figur, fest aus der Session-ID abgeleitet (dieselbe Session sieht immer gleich aus).
public struct OfficeLook: Equatable, Hashable, Sendable {
    public var hair: RGBA
    public var skin: RGBA

    static let hairs: [UInt32] = [0x1E1A18, 0x4A3020, 0xC9A25A, 0x7A3B1E, 0x2E2E36, 0x8C8C94]
    static let skins: [UInt32] = [0xF1C9A5, 0xE0B08A, 0xC68B5E, 0x9C6B45, 0x6E4A32]

    public init(sessionID: String) {
        // FNV-1a: stabil über Programmstarts hinweg (anders als `hashValue`).
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in sessionID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        hair = RGBA(hex: Self.hairs[Int(hash % UInt64(Self.hairs.count))])
        skin = RGBA(hex: Self.skins[Int((hash / 7) % UInt64(Self.skins.count))])
    }
}

/// Pixel-Figuren, 12 × 21 Pixel. Claude Code trägt einen Hoodie in seiner Farbe mit Kapuze und Kordeln,
/// Codex eine offene Jacke in seiner Farbe über weißem Shirt und eine schwarze Cap.
/// Zeichen: H Haar, S Haut, E Augen, O Kragen/Kapuze, B Oberteil, D dunkles Detail, W helles Detail,
/// C Cap, P Hose, K Schuhe, N Dose.
public enum OfficeSprites {
    public static let width = 12

    // MARK: Köpfe

    public static func head(_ agent: AgentKind, facing: Facing) -> [String] {
        switch (agent, facing) {
        case (.claude, .down): [
            "....HHHH....",
            "...HHHHHH...",
            "..HHHHHHHH..",
            "..HSSSSSSH..",
            "..SSESSESS..",
            "..SSSSSSSS..",
            "...SSSSSS...",
            "..OOOSSOOO..",
        ]
        case (.claude, .up): [
            "....HHHH....",
            "...HHHHHH...",
            "..HHHHHHHH..",
            "..HHHHHHHH..",
            "..HHHHHHHH..",
            "..SHHHHHHS..",
            "...HHHHHH...",
            "..OOOOOOOO..",
        ]
        case (.claude, _): [
            "....HHHH....",
            "...HHHHHH...",
            "...HHHHHHH..",
            "...HHHSSSS..",
            "...OHHSSES..",
            "...OHSSSSS..",
            "...OOSSSS...",
            "...OOOSS....",
        ]
        case (.codex, .down): [
            "...CCCCCC...",
            "..CCCCCCCC..",
            "..CCCCCCCC..",
            ".CCCCCCCCCC.",
            "..HSSSSSSH..",
            "..SSESSESS..",
            "...SSSSSS...",
            "...OSSSSO...",
        ]
        case (.codex, .up): [
            "...CCCCCC...",
            "..CCCCCCCC..",
            "..CCCSSCCC..",
            "..CCCCCCCC..",
            "..HHHHHHHH..",
            "..SHHHHHHS..",
            "...HHHHHH...",
            "...OOOOOO...",
        ]
        case (.codex, _): [
            "...CCCCC....",
            "..CCCCCCC...",
            "..CCCCCCCCCC",
            "...HHSSSS...",
            "...HHSSES...",
            "...HSSSSS...",
            "....SSSS....",
            "...OOSS.....",
        ]
        }
    }

    // MARK: Körper

    static func torsoFront(_ agent: AgentKind) -> [String] {
        agent == .claude ? [
            ".BBBBBBBBBB.",
            ".BBBWBBWBBB.",
            ".BBBWBBWBBB.",
            ".BBBBBBBBBB.",
            ".SBBBBBBBBS.",
            ".SBBDDDDBBS.",
            "..BBBBBBBB..",
        ] : [
            ".BBBBWWBBBB.",
            ".BBBBWWBBBB.",
            ".BBBBWWBBBB.",
            ".BBBBWWBBBB.",
            ".SBBBWWBBBS.",
            ".SBBBWWBBBS.",
            "..BBBDDBBB..",
        ]
    }

    static func torsoBack(_ agent: AgentKind) -> [String] {
        agent == .claude ? [
            ".BBOOOOOOBB.",
            ".BBBOOOOBBB.",
            ".BBBBBBBBBB.",
            ".BBBBBBBBBB.",
            ".SBBBBBBBBS.",
            ".SBBBBBBBBS.",
            "..BBBBBBBB..",
        ] : [
            ".BBBBBBBBBB.",
            ".BBBBBBBBBB.",
            ".BBBBBBBBBB.",
            ".BBBBBBBBBB.",
            ".SBBBBBBBBS.",
            ".SBBDDDDBBS.",
            "..BBBBBBBB..",
        ]
    }

    static func torsoSide(_ agent: AgentKind) -> [String] {
        agent == .claude ? [
            "...BBBBBB...",
            "...BBBBBBB..",
            "...BBBBBBB..",
            "...BBBBSB...",
            "...BBBBBS...",
            "...BDDDBB...",
            "...BBBBBB...",
        ] : [
            "...BBBBWB...",
            "...BBBBWBB..",
            "...BBBBWBB..",
            "...BBBBSB...",
            "...BBBBBS...",
            "...BBBBWB...",
            "...BBBBBB...",
        ]
    }

    static let legsFront = [
        "..PPPPPPPP..",
        "..PPPPPPPP..",
        "..PPP..PPP..",
        "..PPP..PPP..",
        "..PPP..PPP..",
        "..KKK..KKK..",
    ]
    static let legsFrontStep = [
        [
            "..PPPPPPPP..",
            "..PPPPPPPP..",
            "..PPP..PPP..",
            "..PPP..PPP..",
            "..PPP..KKK..",
            "..KKK.......",
        ],
        [
            "..PPPPPPPP..",
            "..PPPPPPPP..",
            "..PPP..PPP..",
            "..PPP..PPP..",
            "..KKK..PPP..",
            ".......KKK..",
        ],
    ]
    static let legsSide = [
        "....PPPP....",
        "....PPPP....",
        "....PPPP....",
        "....PPPP....",
        "....PPPP....",
        "....KKKKK...",
    ]
    static let legsSideStep = [
        [
            "....PPPP....",
            "...PPPPPP...",
            "...PP..PP...",
            "..PP....PP..",
            "..PP....PP..",
            ".KKK....KKK.",
        ],
        [
            "....PPPP....",
            "....PPPP....",
            "....PPPP....",
            "....PPPP....",
            "....PPPP....",
            "....KKKKK...",
        ],
    ]

    // MARK: Sitzen und Liegen

    /// Am Tisch im Profil (schaut nach rechts), Hände an der Tastatur.
    static func sitDesk(_ agent: AgentKind, typing: Bool) -> [String] {
        head(agent, facing: .right) + [
            "...BBBBBB...",
            typing ? "...BBBBBBSS." : "...BBBBBBBS.",
            typing ? "...BBBBBB..." : "...BBBBBB.S.",
            "...BBBBBB...",
            "...PPPPPPP..",
            "...PPPPPPPP.",
            "........PP..",
            "........PP..",
            "........PP..",
            "........KKK.",
        ]
    }

    /// Auf der Couch von vorn, wahlweise mit Dose in der Hand.
    static func sitCouch(_ agent: AgentKind, drinking: Bool) -> [String] {
        var torso = torsoFront(agent)
        if drinking {
            torso[3] = ".BBBBBBBBNN."
            torso[4] = ".SBBBBBBBNN."
            torso[5] = torso[5].replacingCharacter(at: 10, with: "S")
        }
        return head(agent, facing: .down) + Array(torso.prefix(6)) + [
            "..PPPPPPPP..",
            "..PPPPPPPP..",
            "..PP....PP..",
            "..KK....KK..",
        ]
    }

    /// Im Bett: Kopf auf dem Kissen (rechts), der Rest unter der Bettdecke. 20 × 9.
    static let lying = [
        "............HHHH....",
        "...........HHHHHH...",
        "DDDDDDDDDDDDHSSSSH..",
        "DDDDDDDDDDDDS-SS-S..",
        "DLDDDDLDDDDDSSSSSS..",
        "DDDDDDDDDDDDOSSSSO..",
        "DDDLDDDDDLDDDDDDDD..",
        "DDDDDDDDDDDDDDDDDD..",
        "DDDDDDDDDDDDDDDDDD..",
    ]

    /// Zeilen einer Figur in einer Haltung. Seitlich nach links wird beim Zeichnen gespiegelt.
    public static func rows(agent: AgentKind, pose: OfficePose, facing: Facing) -> [String] {
        switch pose {
        case .stand:
            switch facing {
            case .down: return head(agent, facing: .down) + torsoFront(agent) + legsFront
            case .up: return head(agent, facing: .up) + torsoBack(agent) + legsFront
            case .left, .right: return head(agent, facing: .right) + torsoSide(agent) + legsSide
            }
        case .walk(let frame):
            let step = frame % 2
            switch facing {
            case .down: return head(agent, facing: .down) + torsoFront(agent) + legsFrontStep[step]
            case .up: return head(agent, facing: .up) + torsoBack(agent) + legsFrontStep[step]
            case .left, .right: return head(agent, facing: .right) + torsoSide(agent) + legsSideStep[step]
            }
        case .sitDesk(let typing): return sitDesk(agent, typing: typing)
        case .sitCouch(let drinking): return sitCouch(agent, drinking: drinking)
        case .lie: return lying
        }
    }

    /// Farben je Agent; das Oberteil in der Agentenfarbe aus den Einstellungen.
    public static func outfit(for agent: AgentKind, color: RGBA) -> [Character: RGBA] {
        var palette: [Character: RGBA] = [
            "E": RGBA(hex: 0x1A1A1E),
            "-": RGBA(hex: 0x3A2A24),
            "B": color,
            "D": color.shaded(0.72),
            "O": color.shaded(0.84),
            "P": RGBA(hex: 0x262A36),
            "K": RGBA(hex: 0xECECF0),
            "N": RGBA(hex: 0x2A55B8),
            "L": RGBA(hex: 0x262832),
        ]
        switch agent {
        case .claude:
            palette["W"] = RGBA(hex: 0xF5E8DA)
        case .codex:
            palette["W"] = RGBA(hex: 0xF2F4FA)
            palette["C"] = RGBA(hex: 0x15161B)
            palette["P"] = RGBA(hex: 0x2B3A55)
        }
        return palette
    }

    /// Zeichnet eine Figur mit dem Fußpunkt `feet` (unten mittig).
    public static func draw(_ canvas: inout PixelCanvas, agent: AgentKind, look: OfficeLook, outfit: [Character: RGBA],
                            pose: OfficePose, facing: Facing, at feet: PixelPoint) {
        let rows = rows(agent: agent, pose: pose, facing: facing)
        var palette = outfit
        palette["H"] = look.hair
        palette["S"] = look.skin
        palette["D"] = pose == .lie ? RGBA(hex: 0x30323C) : outfit["D"]
        let w = rows.first?.count ?? width
        let x = Int(feet.x.rounded()) - w / 2
        let y = Int(feet.y.rounded()) - rows.count
        // Weicher Schatten unter den Füßen (nicht im Bett und nicht im Sitzen).
        if case .stand = pose { canvas.ellipse(x + 2, y + rows.count - 2, 8, 3, RGBA(0, 0, 0, 70)) }
        if case .walk = pose { canvas.ellipse(x + 2, y + rows.count - 2, 8, 3, RGBA(0, 0, 0, 70)) }
        canvas.sprite(rows, palette: palette, at: x, y, flipped: facing == .left)
    }
}

private extension String {
    func replacingCharacter(at index: Int, with character: Character) -> String {
        var chars = Array(self)
        guard index < chars.count else { return self }
        chars[index] = character
        return String(chars)
    }
}
