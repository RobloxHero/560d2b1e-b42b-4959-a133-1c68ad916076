//
//  ViewController.swift
//  560d2b1e-b42b-4959-a133-1c68ad916076
//
//  Created by Ryan on 1/6/26.
//

import UIKit

final class ViewController: UIViewController {
    private let urlField = UITextField()
    private let statusLabel = UILabel()
    private let toggleButton = UIButton(type: .system)
    private let backgroundSwitch = UISwitch()
    private var isStreaming = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Sensor Telemetry"
        titleLabel.font = .preferredFont(forTextStyle: .title2)

        urlField.borderStyle = .roundedRect
        urlField.placeholder = "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry/IPHONE-DATA"
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.text = SensorStreamingClient.shared.webSocketURL.absoluteString

        toggleButton.setTitle("Start Streaming", for: .normal)
        toggleButton.addTarget(self, action: #selector(toggleStreaming), for: .touchUpInside)

        let backgroundLabel = UILabel()
        backgroundLabel.text = "Background streaming"
        backgroundLabel.font = .preferredFont(forTextStyle: .body)

        backgroundSwitch.addTarget(self, action: #selector(backgroundPreferenceChanged(_:)), for: .valueChanged)

        statusLabel.text = "Idle"
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        let backgroundRow = UIStackView(arrangedSubviews: [backgroundLabel, backgroundSwitch])
        backgroundRow.axis = .horizontal
        backgroundRow.spacing = 12
        backgroundRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, urlField, toggleButton, backgroundRow, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func toggleStreaming() {
        guard let urlText = urlField.text, let url = URL(string: urlText) else {
            updateStatus("Invalid WebSocket URL")
            return
        }

        SensorStreamingClient.shared.webSocketURL = url
        SensorStreamingClient.shared.allowsBackgroundStreaming = backgroundSwitch.isOn

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

    private func updateStatus(_ message: String) {
        statusLabel.text = message
    }
}
