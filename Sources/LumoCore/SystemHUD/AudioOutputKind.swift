import Foundation

/// Symbol für ein Audiogerät, aus Namen und Anschlussart (Core-Audio-Transporttyp als Vier-Zeichen-Code).
public enum AudioOutputKind {
    public static func symbol(name: String, transport: String?) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("homepod") { return "homepod.fill" }
        if lower.contains("kopfhörer") || lower.contains("headphone") || lower.contains("buds") { return "headphones" }
        switch transport {
        case "blue": return "headphones"
        case "bltn": return "laptopcomputer"
        case "dprt", "hdmi": return "display"
        case "airp": return "airplayaudio"
        case "usb ", "usb": return "hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    /// Transporttyp von Core Audio (`kAudioDevicePropertyTransportType`) als lesbarer Vier-Zeichen-Code.
    public static func transportCode(_ value: UInt32) -> String {
        let bytes = [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
