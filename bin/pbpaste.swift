#!/usr/bin/env swift

import Cocoa
let type = NSPasteboard.PasteboardType.html
if let string = NSPasteboard.general.string(forType:type) {
  print(string)
}
else {
  print("Could not find string data of type '\(type)' on the system pasteboard")
  print("Available types on the pasteboard:")
  if let availableTypes = NSPasteboard.general.types {
    for availableType in availableTypes {
      print(availableType)
    }
  }
  exit(1)
}