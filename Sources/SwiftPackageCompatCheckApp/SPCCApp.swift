import ArgumentParser
import SwiftPackageCompatCheck

@main
struct SPCCApp {
    static func main() async {
        await SPCC.main()
    }
}
