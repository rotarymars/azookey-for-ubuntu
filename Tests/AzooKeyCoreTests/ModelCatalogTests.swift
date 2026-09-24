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
}
