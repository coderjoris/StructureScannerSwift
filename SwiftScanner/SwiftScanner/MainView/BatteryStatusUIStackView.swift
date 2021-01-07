//
//  BatteryStatusUIStackView.swift
//  SwiftScanner
//
//  Created by Windmolders Joris on 05/06/2020.
//  Copyright © 2020 CoderJoris. All rights reserved.
//

import Foundation
import UIKit

class BatteryStatusUIStackView: UIStackView, BatteryStatusListenerDelegate {
            
    private var label = UILabel()
    private var imageView = UIImageView()
    private var monitor: BatteryStatusMonitor?
    
    /*
     // Only override draw() if you perform custom drawing.
     // An empty implementation adversely affects performance during animation.
     override func draw(_ rect: CGRect) {
     // Drawing code
     }
     */
    
    //Mark: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
     
        setupControls()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        
        setupControls()
    }
    
    private func setupControls() {
        // image
        let imageName = "SensorBatteryLow"
        let image = UIImage(named: imageName)
        self.imageView = UIImageView(image: image!)
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.imageView.widthAnchor.constraint(equalToConstant: 100.0).isActive = true
        self.imageView.isHidden = true

        // label - no size constraints! Size is calculated after setting text and
        // label is centered in stackview
        label.font = label.font.withSize(12)
        label.textAlignment = .center
        label.textColor = UIColor.darkGray
        self.label.text = ""

        addArrangedSubview(self.imageView)
        addArrangedSubview(self.label)
    }
    
    // Mark: - External control
    public func start() {
        if monitor == nil {
            monitor = BatteryStatusMonitor()
            monitor?._delegate = self
        }
        
        monitor?.start()
    }
    
    public func stop() {
        monitor?.stop()
    }
    
    //MARK: BatteryStatusListenerDelegate
    func updateBatteryStatus(level: Int32) {
        let pcttext = String(format: "%02d", level)
        self.label.text = "Sensor battery: \(pcttext)%"
        self.label.sizeToFit()
        self.imageView.isHidden = level > 5
    }
    
    func batteryStatusUnknown() {
        self.label.text = ""
        self.imageView.isHidden = true
    }
}
