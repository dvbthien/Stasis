import AppKit
import Defaults
import SwiftUI

@MainActor
class StatusBarManager {
    private let statusItem: NSStatusItem
    private let viewModel: MenuViewModel
    
    // Lưu lại các kết nối để tránh giải phóng bộ nhớ ngầm
    private var locationObservation: Defaults.Observation?
    private var showStateObservation: Defaults.Observation?

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Cấu hình nút ban đầu
        if let button = statusItem.button {
            button.title = ""
        }
        
        // Kích hoạt hệ thống lắng nghe tự động
        setupDefaultsObservations()
        startViewModelObservation()
    }

    func setMenu(_ menu: NSMenu) {
        statusItem.menu = menu
    }

    /// 1. Tự động lắng nghe thay đổi từ @Observable ViewModel
    private func startViewModelObservation() {
        withObservationTracking {
            // Chỉ cần chạm vào các thuộc tính này, Swift sẽ biết cần phải theo dõi chúng
            _ = viewModel.displayPercentage
            _ = viewModel.chargingMode
            _ = viewModel.isLowPowerModeEnabled
        } onChange: { [weak self] in
            // Khi có bất kỳ thuộc tính nào ở trên đổi số, hàm này lập tức được gọi
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusIcon()
                self.startViewModelObservation() // Tiếp tục theo dõi vòng tiếp theo
            }
        }
    }

    /// 2. Tự động lắng nghe thay đổi từ UserDefaults (Thư viện Defaults)
    private func setupDefaultsObservations() {
        locationObservation = Defaults.observe(.batteryPercentageDisplayLocation) { [weak self] _ in
            self?.updateStatusIcon()
        }
        showStateObservation = Defaults.observe(.showBatteryStateInStatusIcon) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    /// 3. Hàm duy nhất chịu trách nhiệm render và gán ảnh trực tiếp
    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        
        let percentageDisplayLocation = Defaults[.batteryPercentageDisplayLocation]
        let showState = Defaults[.showBatteryStateInStatusIcon]

        // Gọi trực tiếp bộ vẽ ra NSImage
        let batteryImage = BatteryRenderer.render(
            level: viewModel.displayPercentage,
            chargingMode: viewModel.chargingMode,
            isLowPower: viewModel.isLowPowerModeEnabled,
            displayLocation: percentageDisplayLocation,
            showState: showState
        )

        // Gán thẳng vào button của AppKit
        button.image = batteryImage
        button.imagePosition = (percentageDisplayLocation == .nextToIcon) ? .imageLeft : .imageOnly
    }
}


