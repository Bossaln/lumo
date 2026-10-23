import Foundation

/// Tageslicht im Büro aus dem echten Sonnenstand, ohne Ortungsberechtigung: Ort aus den Einstellungen,
/// sonst grob aus der Zeitzone (Konzept: „wie der Sonnenstand ohne Ortungsberechtigung ermittelt wird“).
public enum Daylight {
    /// Höhe der Sonne über dem Horizont in Grad (Näherung nach NOAA, auf etwa 1° genau).
    public static func sunElevation(date: Date, latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let meanLongitude = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let anomaly = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let siderealHours = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let hourAngle = (siderealHours * 15 + longitude) * rad - rightAscension
        let lat = latitude * rad
        return asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)) / rad
    }

    /// 0 = Nacht, 1 = Tag; dazwischen weich über die Dämmerung (−6° bis +6°).
    public static func level(elevation: Double) -> Double {
        let t = min(max((elevation + 6) / 12, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Ort für den Sonnenstand: aus den Einstellungen, sonst Länge aus der Zeitzone und Breite 50°.
    public static func location(latitude: Double?, longitude: Double?, timeZone: TimeZone, date: Date)
        -> (latitude: Double, longitude: Double) {
        if let latitude, let longitude { return (latitude, longitude) }
        let hours = Double(timeZone.secondsFromGMT(for: date)) / 3600
        return (latitude ?? 50, longitude ?? hours * 15)
    }

    /// Tageslicht nach der Einstellung „Beleuchtung“.
    public static func level(settings: AppSettings, date: Date, timeZone: TimeZone = .current) -> Double {
        switch settings.officeLighting {
        case .fixedDay: return 1
        case .fixedNight: return 0
        case .realSun:
            let place = location(latitude: settings.officeLatitude, longitude: settings.officeLongitude,
                                 timeZone: timeZone, date: date)
            return level(elevation: sunElevation(date: date, latitude: place.latitude, longitude: place.longitude))
        }
    }
}
