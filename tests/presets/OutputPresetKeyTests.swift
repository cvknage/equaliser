import XCTest
@testable import Equaliser

final class OutputPresetKeyTests: XCTestCase {
    func testUSBDeviceWithoutSerialIgnoresPort() {
        // UIDs reported by a serial-less JDS Labs Atom DAC+ on three different ports.
        let keys = Set(["1100000", "1140000", "2140000"].map {
            OutputPresetKey.make(for: "AppleUSBAudioEngine:JDS Labs:JDS Labs Atom DAC+:\($0):1")
        })
        XCTAssertEqual(keys, ["AppleUSBAudioEngine:JDS Labs:JDS Labs Atom DAC+::1"])
    }

    func testKeyIsIdempotent() {
        let key = OutputPresetKey.make(for: "AppleUSBAudioEngine:Acme:DAC:14200000:1")
        XCTAssertEqual(OutputPresetKey.make(for: key), key)
    }

    func testSerialNumbersKeepDevicesDistinct() {
        for uid in [
            "AppleUSBAudioEngine:Focusrite:Scarlett 2i2 USB:Y8XKJ4X1234567:1",
            "AppleUSBAudioEngine:Acme:DAC:0001:1",
            "AppleUSBAudioEngine:Acme:DAC:123456789:1",
        ] {
            XCTAssertEqual(OutputPresetKey.make(for: uid), uid)
        }
    }

    func testInterfacesStayDistinct() {
        XCTAssertNotEqual(
            OutputPresetKey.make(for: "AppleUSBAudioEngine:Acme:DAC:2140000:1"),
            OutputPresetKey.make(for: "AppleUSBAudioEngine:Acme:DAC:2140000:2")
        )
    }

    func testProductNameMayContainColons() {
        XCTAssertEqual(
            OutputPresetKey.make(for: "AppleUSBAudioEngine:Acme:DAC: Pro:2140000:1"),
            "AppleUSBAudioEngine:Acme:DAC: Pro::1"
        )
    }

    func testNonUSBUIDsAreUnchanged() {
        for uid in [
            "BuiltInSpeakerDevice",
            "5C-D3-3D-D6-96-8B:output",
            "10AC6A43-0000-0000-0E24-0104B53C2278",
            "zoom.us.zoomaudiodevice.001",
        ] {
            XCTAssertEqual(OutputPresetKey.make(for: uid), uid)
        }
    }
}
