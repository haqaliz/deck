import Testing
import Foundation
@testable import SettingsCore

func decode<T: Decodable>(_ json: String, as _: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

@Suite("OpenBox tolerant decode")
struct OpenBoxTests {
    @Test("missing keys fall back to defaults")
    func missingKeys() throws {
        let s = try decode(#"{"token":"abc","refreshInterval":30,"showChart":false}"#, as: OpenBox.self)
        #expect(s.token == "abc")
        #expect(s.serverURL == nil)
        #expect(s.refreshInterval == 30)
        #expect(s.showChart == false)
        #expect(s.showModels == true)
        #expect(s.inputColor == RGBA.cyan)
        #expect(s.outputColor == RGBA.green)
        #expect(s.costColor == RGBA.orange)
    }

    @Test("full fixture decodes exact values")
    func full() throws {
        let json = """
        {"token":"t","serverURL":"http://h:4096","refreshInterval":5,"showChart":false,"showModels":false,
         "inputColor":{"red":0.1,"green":0.2,"blue":0.3,"alpha":0.4},
         "outputColor":{"red":0.5,"green":0.6,"blue":0.7,"alpha":0.8},
         "costColor":{"red":0.9,"green":0.8,"blue":0.7,"alpha":0.6}}
        """
        let s = try decode(json, as: OpenBox.self)
        #expect(s == OpenBox(
            token: "t",
            serverURL: "http://h:4096",
            refreshInterval: 5,
            showChart: false,
            showModels: false,
            inputColor: RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            outputColor: RGBA(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8),
            costColor: RGBA(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.6)
        ))
    }

    @Test("explicit null serverURL decodes nil")
    func nullServerURL() throws {
        let s = try decode(#"{"serverURL":null}"#, as: OpenBox.self)
        #expect(s.serverURL == nil)
    }

    @Test("type mismatch still throws")
    func typeMismatch() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"showChart":"yes"}"#, as: OpenBox.self)
        }
    }

    @Test("unknown keys are ignored")
    func unknownKeys() throws {
        let s = try decode(#"{"bogus":123,"showChart":false}"#, as: OpenBox.self)
        #expect(s.showChart == false)
        #expect(s.refreshInterval == 60)
    }

    @Test("encode round-trip preserves values")
    func roundTrip() throws {
        let s = OpenBox(token: "t", serverURL: "http://h:4096", refreshInterval: 5,
                         showChart: false, showModels: true,
                         inputColor: RGBA(red: 0.1, green: 0.2, blue: 0.3),
                         outputColor: .green, costColor: .orange)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(OpenBox.self, from: data)
        #expect(back == s)
    }
}

@Suite("NetBox tolerant decode")
struct NetBoxTests {
    @Test("empty fixture decodes all defaults")
    func empty() throws {
        let s = try decode(#"{}"#, as: NetBox.self)
        #expect(s == NetBox())
    }

    @Test("partial fixture keeps defaults")
    func partial() throws {
        let s = try decode(#"{"interfaceCount":7}"#, as: NetBox.self)
        #expect(s.interfaceCount == 7)
        #expect(s.showChart == true)
        #expect(s.upColor == RGBA.green)
    }
}

@Suite("BatBox tolerant decode")
struct BatBoxTests {
    @Test("missing keys fall back to defaults")
    func missingKeys() throws {
        let s = try decode(#"{"showChart":false}"#, as: BatBox.self)
        #expect(s.showChart == false)
        #expect(s.showStatus == true)
        #expect(s.levelColor == RGBA.green)
    }
}

@Suite("GitBox tolerant decode")
struct GitBoxTests {
    @Test("missing keys fall back to defaults")
    func missingKeys() throws {
        let s = try decode(#"{"repoPaths":["/a","/b"],"barColor":{"red":1,"green":0,"blue":0,"alpha":1}}"#, as: GitBox.self)
        #expect(s.repoPaths == ["/a", "/b"])
        #expect(s.barColor == RGBA(red: 1, green: 0, blue: 0))
        #expect(s.repoCount == 5)
        #expect(s.scanDepth == 3)
        #expect(s.todayColor == RGBA.orange)
    }

    @Test("missing repoPaths decodes empty")
    func missingRepoPaths() throws {
        let s = try decode(#"{}"#, as: GitBox.self)
        #expect(s.repoPaths == [])
    }
}

@Suite("DevBox tolerant decode")
struct DevBoxTests {
    @Test("empty fixture decodes all defaults")
    func empty() throws {
        let s = try decode(#"{}"#, as: DevBox.self)
        #expect(s == DevBox())
    }
}
