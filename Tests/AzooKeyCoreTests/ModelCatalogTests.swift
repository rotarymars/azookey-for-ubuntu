import AzooKeyCore
import Foundation
import Testing

@Suite struct ModelCatalogTests {
    @Test func legacyModelNamesStillLoad() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"zenzaiModel": "xsmall"}"#.utf8))
        #expect(settings.zenzaiModel == "zenz-v3.2-xsmall")
        #expect(Settings().zenzaiModel == ModelCatalog.defaultModelID)
    }

    @Test func onlyV32ModelsGetRightContext() {
        #expect(ModelCatalog.supportsRightContext("zenz-v3.2-small"))
        #expect(!ModelCatalog.supportsRightContext("zenz-v3.1-small"))
    }

    @Test func localModelFileIsUsedWhenItExists() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("azookey-local-\(UUID().uuidString).gguf")
        defer { try? FileManager.default.removeItem(at: file) }
        let json = #"{"zenzaiModel": "local", "zenzaiLocalModelPath": "\#(file.path)", "zenzaiLocalModelRightContext": true}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.zenzaiModel == ModelCatalog.localModelID)

        // Missing: falls back to a catalog model (or none).
        #expect(ModelCatalog.resolve(settings)?.file != file)

        #expect(FileManager.default.createFile(atPath: file.path, contents: Data()))
        let model = try #require(ModelCatalog.resolve(settings))
        #expect(model.file.path == file.path)
        #expect(model.rightContext)
    }
}
