//
//  ViewController.swift
//  560d2b1e-b42b-4959-a133-1c68ad916076
//
//  Created by Ryan on 1/6/26.
//

import UIKit

final class ViewController: UIViewController {
    private let baseURLField = UITextField()
    private let parameterField = UITextField()
    private let statusLabel = UILabel()
    private let toggleButton = UIButton(type: .system)
    private let backgroundSwitch = UISwitch()
    private let locationSwitch = UISwitch()
    private let cameraLightSwitch = UISwitch()
    private let pictureSwitch = UISwitch()
    private let gyroSwitch = UISwitch()
    private let intervalControl = UISegmentedControl(items: ["60Hz", "20Hz", "10Hz", "4Hz"])
    private let intervalValues: [TimeInterval] = [1.0 / 60.0, 0.05, 0.1, 0.25]
    private var isStreaming = false
    private var streamOptions = SensorStreamingClient.StreamOptions()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Sensor Telemetry"
        titleLabel.font = .preferredFont(forTextStyle: .title2)

        baseURLField.borderStyle = .roundedRect
        baseURLField.placeholder = "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry"
        baseURLField.keyboardType = .URL
        baseURLField.autocapitalizationType = .none
        baseURLField.autocorrectionType = .no
        baseURLField.text = "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry"
        baseURLField.addTarget(self, action: #selector(urlFieldEditingDidEnd), for: [.editingDidEnd, .editingDidEndOnExit])

        parameterField.borderStyle = .roundedRect
        parameterField.placeholder = "IPHONE-DATA"
        parameterField.autocapitalizationType = .allCharacters
        parameterField.text = "IPHONE-DATA"
        parameterField.addTarget(self, action: #selector(urlFieldEditingDidEnd), for: [.editingDidEnd, .editingDidEndOnExit])

        let intervalLabel = UILabel()
        intervalLabel.text = "Stream Interval"
        intervalLabel.font = .preferredFont(forTextStyle: .body)
        intervalControl.selectedSegmentIndex = 2
        intervalControl.addTarget(self, action: #selector(intervalChanged(_:)), for: .valueChanged)
        let intervalStack = UIStackView(arrangedSubviews: [intervalLabel, intervalControl])
        intervalStack.axis = .vertical
        intervalStack.spacing = 8

        toggleButton.setTitle("Start Streaming", for: .normal)
        toggleButton.addTarget(self, action: #selector(toggleStreaming), for: .touchUpInside)

        let backgroundRow = makeSwitchRow(title: "Background streaming", toggleSwitch: backgroundSwitch, action: #selector(backgroundPreferenceChanged(_:)))
        let locationRow = makeSwitchRow(title: "Include Location", toggleSwitch: locationSwitch, action: #selector(optionSwitchChanged(_:)))
        let cameraRow = makeSwitchRow(title: "Camera Light Sensor", toggleSwitch: cameraLightSwitch, action: #selector(optionSwitchChanged(_:)))
        let pictureRow = makeSwitchRow(title: "Picture Data", toggleSwitch: pictureSwitch, action: #selector(optionSwitchChanged(_:)))
        let gyroRow = makeSwitchRow(title: "Gyroscope", toggleSwitch: gyroSwitch, action: #selector(optionSwitchChanged(_:)))
        gyroSwitch.isOn = true

        statusLabel.text = "Idle"
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        let toggleStack = UIStackView(arrangedSubviews: [locationRow, cameraRow, pictureRow, gyroRow])
        toggleStack.axis = .vertical
        toggleStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            baseURLField,
            parameterField,
            intervalStack,
            toggleButton,
            backgroundRow,
            toggleStack,
            statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        SensorStreamingClient.shared.updateOptions(streamOptions)
        applyIntervalSelection()
    }

    private func makeSwitchRow(title: String, toggleSwitch: UISwitch, action: Selector) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        toggleSwitch.addTarget(self, action: action, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [label, toggleSwitch])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    @objc private func toggleStreaming() {
        guard let url = buildWebSocketURL() else {
            updateStatus("Invalid WebSocket URL")
            return
        }

        SensorStreamingClient.shared.webSocketURL = url
        SensorStreamingClient.shared.allowsBackgroundStreaming = backgroundSwitch.isOn

        SensorStreamingClient.shared.updateOptions(streamOptions)

        if isStreaming {
            SensorStreamingClient.shared.stopStreaming()
            isStreaming = false
            toggleButton.setTitle("Start Streaming", for: .normal)
            updateStatus("Stopped")
        } else {
            SensorStreamingClient.shared.startStreaming()
            isStreaming = true
            toggleButton.setTitle("Stop Streaming", for: .normal)
            updateStatus("Streaming to \(url.absoluteString)")
        }
    }

    @objc private func backgroundPreferenceChanged(_ sender: UISwitch) {
        SensorStreamingClient.shared.allowsBackgroundStreaming = sender.isOn
    }

    @objc private func optionSwitchChanged(_ sender: UISwitch) {
        streamOptions.includeLocation = locationSwitch.isOn
        streamOptions.includeCameraLight = cameraLightSwitch.isOn
        streamOptions.includePictureData = pictureSwitch.isOn
        streamOptions.includeGyroscope = gyroSwitch.isOn
        SensorStreamingClient.shared.updateOptions(streamOptions)
    }

    @objc private func intervalChanged(_ sender: UISegmentedControl) {
        applyIntervalSelection()
    }

    @objc private func urlFieldEditingDidEnd() {
        guard isStreaming, let url = buildWebSocketURL() else { return }
        SensorStreamingClient.shared.webSocketURL = url
        updateStatus("Streaming to \(url.absoluteString)")
    }

    private func applyIntervalSelection() {
        let index = intervalControl.selectedSegmentIndex >= 0 ? intervalControl.selectedSegmentIndex : 2
        let interval = intervalValues[index]
        SensorStreamingClient.shared.updateStreamInterval(interval)
    }

    private func buildWebSocketURL() -> URL? {
        guard let base = baseURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.isEmpty,
              let parameter = parameterField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !parameter.isEmpty else {
            return nil
        }

        let separator = base.hasSuffix("/") ? "" : "/"
        return URL(string: "\(base)\(separator)\(parameter)")
    }

    private func updateStatus(_ message: String) {
        statusLabel.text = message
    }
}
