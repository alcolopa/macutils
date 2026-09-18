import AppKit

public final class PreferencesTabViewController: NSTabViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.tabStyle = .toolbar
        
        // 1. General & Order Tab
        let generalVC = GeneralSettingsViewController()
        let generalItem = NSTabViewItem(viewController: generalVC)
        generalItem.label = "General"
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        addTabViewItem(generalItem)
        
        // 2. Metric Tabs
        let metricConfigs: [(MetricType, String, String)] = [
            (.cpu, "CPU", "cpu"),
            (.memory, "Memory", "memorychip"),
            (.temperatures, "Temps", "thermometer.medium"),
            (.weather, "Weather", "cloud.sun.fill"),
            (.displays, "Displays", "display"),
            (.disk, "Disk", "internaldrive"),
            (.network, "Network", "network"),
            (.battery, "Battery", "battery.100")
        ]
        
        for (metric, label, iconName) in metricConfigs {
            let vc = MetricSettingsViewController(metric: metric)
            let item = NSTabViewItem(viewController: vc)
            item.label = label
            item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: label)
            addTabViewItem(item)
        }
    }
}
