import Foundation

struct MTPDeviceSummary: Equatable {
    let manufacturer: String?
    let model: String?
    let deviceVersion: String?
    let serialNumber: String?
    let usbVendorID: Int?
    let usbProductID: Int?
    
    var displayName: String {
        if let model, !model.isEmpty {
            return model
        }
        if let manufacturer, !manufacturer.isEmpty {
            return manufacturer
        }
        return "Android Device"
    }
    
    var detail: String {
        let parts = [
            manufacturer,
            deviceVersion,
            serialNumber.map { "S/N \($0)" }
        ].compactMap { $0 }.filter { !$0.isEmpty }
        
        return parts.isEmpty ? "MTP device" : parts.joined(separator: " · ")
    }
    
    static func from(_ response: KalamResponse) -> MTPDeviceSummary {
        let root = response.data
        let mtp = root?.value(forKeyIgnoringCase: "mtpDeviceInfo")
        let usb = root?.value(forKeyIgnoringCase: "usbDeviceInfo")
        
        return MTPDeviceSummary(
            manufacturer: firstString(from: mtp, keys: ["Manufacturer", "manufacturer"]),
            model: firstString(from: mtp, keys: ["Model", "model", "DeviceName", "Name"]),
            deviceVersion: firstString(from: mtp, keys: ["DeviceVersion", "deviceVersion", "Version"]),
            serialNumber: firstString(from: mtp, keys: ["SerialNumber", "serialNumber"]),
            usbVendorID: firstInt(from: usb, keys: ["VendorID", "vendorId", "idVendor"]),
            usbProductID: firstInt(from: usb, keys: ["ProductID", "productId", "idProduct"])
        )
    }
    
    private static func firstString(from value: KalamJSONValue?, keys: [String]) -> String? {
        value?.firstString(forKeys: keys)
    }
    
    private static func firstInt(from value: KalamJSONValue?, keys: [String]) -> Int? {
        guard let object = value?.objectValue else { return nil }
        for key in keys {
            if let value = object.value(forKeyIgnoringCase: key)?.intValue {
                return value
            }
        }
        return nil
    }
}

struct MTPStorageSummary: Identifiable, Equatable {
    let id: UUID
    let storageID: UInt32
    let name: String
    let maxCapacity: Int64?
    let freeSpace: Int64?
    
    var subtitle: String {
        guard let maxCapacity, let freeSpace, maxCapacity > 0 else {
            return "MTP storage"
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let free = formatter.string(fromByteCount: freeSpace)
        let total = formatter.string(fromByteCount: maxCapacity)
        return "\(free) free of \(total)"
    }
    
    func demoEntry() -> DemoEntry {
        let clampedSize: Int?
        if let maxCapacity {
            clampedSize = Int(exactly: min(maxCapacity, Int64(Int.max)))
        } else {
            clampedSize = nil
        }
        
        return DemoEntry(
            id: id,
            name: name,
            subtitle: subtitle,
            sizeBytes: clampedSize,
            isDirectory: true,
            storageID: storageID,
            remotePath: "/"
        )
    }
    
    static func fromArray(_ value: KalamJSONValue?) -> [MTPStorageSummary] {
        guard let items = value?.arrayValue else { return [] }
        
        return items.compactMap { item in
            guard let object = item.objectValue else { return nil }
            
            let storageObject = object.value(forKeyIgnoringCase: "Info")?.objectValue
                ?? object.value(forKeyIgnoringCase: "info")?.objectValue
                ?? object
            
            guard let rawStorageID = object.value(forKeyIgnoringCase: "Sid")?.intValue
                ?? object.value(forKeyIgnoringCase: "StorageId")?.intValue
                ?? storageObject.value(forKeyIgnoringCase: "StorageID")?.intValue else {
                return nil
            }
            
            let storageName = storageObject.firstString(forKeys: [
                "StorageDescription",
                "storageDescription",
                "VolumeLabel",
                "volumeLabel",
                "Name"
            ]) ?? "MTP Storage \(rawStorageID)"
            
            let maxCapacity = storageObject.value(forKeyIgnoringCase: "MaxCapability")?.intValue
                .map(Int64.init)
                ?? storageObject.value(forKeyIgnoringCase: "MaxCapacity")?.intValue.map(Int64.init)
            
            let freeSpace = storageObject.value(forKeyIgnoringCase: "FreeSpaceInBytes")?.intValue
                .map(Int64.init)
                ?? storageObject.value(forKeyIgnoringCase: "FreeSpace")?.intValue.map(Int64.init)
            
            return MTPStorageSummary(
                id: MTPDirectory.identity(storageID: UInt32(clamping: rawStorageID), objectID: 0),
                storageID: UInt32(clamping: rawStorageID),
                name: storageName,
                maxCapacity: maxCapacity,
                freeSpace: freeSpace
            )
        }
    }
}
