import Foundation
import Cocoa

class ApplicationsLogicController {
  enum PlistKey: String {
    case bundleName = "CFBundleName"
    case bundleIdentifier = "CFBundleIdentifier"
    case requiresAquaSystemAppearance = "NSRequiresAquaSystemAppearance"
  }

  func load(then handler: (ApplicationsViewController.State) -> Void) {
    do {
      let applicationDirectory = try FileManager.default.url(for: .allApplicationsDirectory,
                                                             in: .localDomainMask,
                                                             appropriateFor: nil,
                                                             create: false)
      let urls = try FileManager.default.contentsOfDirectory(at: applicationDirectory,
                                                              includingPropertiesForKeys: nil,
                                                              options: .skipsHiddenFiles)
      let sortedUrls = urls.sorted(by: { $0.absoluteString.lowercased() < $1.absoluteString.lowercased() } )
      let applications = try processApplications(sortedUrls, at: applicationDirectory)
      handler(.list(applications))
    } catch {}
  }

  func toggleAppearance(for application: Application,
                        newAppearance appearance: Application.Appearance,
                        then handler: @escaping (ApplicationsViewController.State) -> Void) {
    DispatchQueue.global(qos: .utility).async {
      let newSetting = appearance == .light ? "YES" : "NO"
      do {
        let shell = Shell()
        let applicationIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier).isEmpty
        if applicationIsRunning {
          var closeScript = String()
          closeScript = closeScript.craft("\"tell application ", "\\", "\"", application.name, "\\", "\" to ", "quit\"")
          try shell.execute(command: "osascript", arguments: ["-e", closeScript])
        }

        try shell.execute(command: "defaults write \(application.bundleIdentifier) NSRequiresAquaSystemAppearance -bool \(newSetting)")

        if applicationIsRunning {
          try shell.execute(command: "open \"\(application.url.path)\"")
        }

        DispatchQueue.main.async { [weak self] in
          self?.load(then: handler)
        }
      } catch {}
    }
  }

  private func processApplications(_ appUrls: [URL], at directoryUrl: URL) throws -> [Application] {
    var applications = [Application]()

    let libraryDirectory = try FileManager.default.url(for: .libraryDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false)

    for url in appUrls {
      let path = url.path
      let infoPath = "\(path)/Contents/Info.plist"
      guard FileManager.default.fileExists(atPath: infoPath),
        let plist = NSDictionary.init(contentsOfFile: infoPath),
        let bundleIdentifier = plist.value(forPlistKey: .bundleIdentifier),
        let bundleName = plist.value(forPlistKey: .bundleName) else { continue }

      let suffix = "Preferences/\(bundleIdentifier).plist"
      let appPreferenceUrl = libraryDirectory.appendingPathComponent(suffix)
      let appContainerPreferenceUrl = libraryDirectory.appendingPathComponent("Containers/\(bundleIdentifier)/Data/Library/\(suffix)")
      var resolvedAppPreferenceUrl = appPreferenceUrl
      var applicationPlist: NSDictionary? = nil

      if let plist = NSDictionary.init(contentsOfFile: appPreferenceUrl.path) {
        applicationPlist = plist
      } else if let plist = NSDictionary.init(contentsOfFile: appContainerPreferenceUrl.path) {
        applicationPlist = plist
        resolvedAppPreferenceUrl = appContainerPreferenceUrl
      }

      guard let resolvedPlist = applicationPlist else { continue }

      let app = Application(bundleIdentifier: bundleIdentifier,
                            name: bundleName,
                            url: url,
                            preferencesUrl: resolvedAppPreferenceUrl,
                            appearance: resolvedPlist.appearance())
      applications.append(app)
    }
    return applications
  }
}

fileprivate extension String {
  mutating func craft(_ strings: String ...) -> String {
    for string in strings {
      self = self.appending(string)
    }

    return self
  }
}

fileprivate extension NSDictionary {
  func appearance() -> Application.Appearance {
    let key = ApplicationsLogicController.PlistKey.requiresAquaSystemAppearance.rawValue
    let result = (value(forKey: key) as? Bool) ?? false
    return result ? .light : .dark
  }

  func value(forPlistKey plistKey: ApplicationsLogicController.PlistKey) -> String? {
    return value(forKey: plistKey.rawValue) as? String
  }
}