import Foundation

/// Static Tuya Mobile SDK identifiers for the Philips Baby Monitor+ app.
/// These are baked into the public Android APK (`com.philips.ph.babymonitorplus`)
/// — functional identifiers like an OAuth client id/secret, identical for every
/// user and containing no personal data. Mirrors `login/const.py`.
public enum TuyaConst {
    public static let signingKey =
        "com.philips.ph.babymonitorplus"
        + "_D2:D6:95:A1:1D:1B:84:F9:25:A9:45:6E:27:F4:45:E9:FD:87:C3:74"
        + ":63:AA:8A:34:32:A6:6A:23:3B:0F:D5:0F"
        + "_8n459nxk9g98gqgcwrpk3csv97uuwajm"
        + "_a3nfht4ufwfw9cmkspaftv4x89cx58qx"
    public static let appKey = "wx3at9qprkhskvkcsyhm"
    public static let packageName = "com.philips.ph.babymonitorplus"
    public static let chKey = "071d81fa"
    public static let apiURL = URL(string: "https://a1.tuyaeu.com/api.json")!
    public static let defaultCountryCode = "47"  // Norway
}
