//
//  ViewController.swift
//
//  Temperature DS18B20-macOS
//
//  Created by Charles Vercauteren on 18/11/2020.
//

import Cocoa
import Network

struct LogEntry {
    var time = ""
    var temperature = ""
}

let MESSAGE_EMPTY = ""
let GET_TEMPERATURE = "10"
let SET_TIME = "20"
let GET_TIME = "21"
let SET_LOG_INTERVAL = "22"
let GET_LOG_INTERVAL = "23"
let GET_LOG = "30"
let GET_HOSTNAME = "40"
let SET_HOSTNAME = "41"

let LOG_INTERVAL = "1800"

let UPDATE_INTERVAL = 1     // Update view

let PORTNUMBER: UInt16 = 2000

// Variable used to return message from NWConnection.receiveMessage closure
var reply = ""

class ViewController: NSViewController {

    @IBOutlet weak var hostNameFromArduino: NSTextField!
    @IBOutlet weak var hostNameForArduino: NSTextField!
    @IBOutlet weak var ipAddress: NSTextField!
    @IBOutlet weak var temperatureOut: NSTextField!
    @IBOutlet weak var timeFromArduino: NSTextField!
    @IBOutlet weak var logInterval: NSTextField!
    @IBOutlet weak var logIntervalFromArduino: NSTextField!
    @IBOutlet weak var logTable: NSTableView!
    @IBOutlet weak var info: NSTextField!
    
    
    @IBOutlet weak var connectBtn: NSButton!
    @IBOutlet weak var setTimeBtn: NSButton!
    @IBOutlet weak var saveLogBtn: NSButton!
    @IBOutlet weak var setLogIntervalBtn: NSButton!
    @IBOutlet weak var setHostNameBtn: NSButton!
    @IBOutlet weak var setTimeOnArduinoBtn: NSButton!
    
    //Update interval properties
    var timer = Timer()
    let interval = TimeInterval(UPDATE_INTERVAL)     //Seconds
    
    // First command to send to Arduino
    var commandToSend = GET_LOG_INTERVAL
    
    //Arduino UDP server properties
    //IP via interface
    let portNumber: UInt16 = PORTNUMBER
    var server: NWConnection?
    
    var log = [LogEntry]()


    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Init
        logInterval.stringValue = LOG_INTERVAL
        
        // Enable/disable buttons
        setTimeBtn.isEnabled = false
        saveLogBtn.isEnabled = false
        setLogIntervalBtn.isEnabled = false
        setTimeOnArduinoBtn.isEnabled = false
        setHostNameBtn.isEnabled = false
        
        //
        info.stringValue = "Please connect to thermometer."
        
        logTable.delegate = self
        logTable.dataSource = self
        
    }

    @IBAction func connect(_ sender: NSButton) {
        // Verbreek huidige verbinding
        timer.invalidate()
        server?.forceCancel()
        // Update display
        info.stringValue = "Connecting."
        hostNameFromArduino.stringValue = "------"
        temperatureOut.stringValue = "--.-- °C"
        timeFromArduino.stringValue = "Time: --:--:--"
        logIntervalFromArduino.stringValue = "Log interval: -- s"

        //Create host
        let host = NWEndpoint.Host(ipAddress.stringValue)
        //Create port
        let port = NWEndpoint.Port(rawValue: portNumber)!
        //Create endpoint
        //if server != nil { server!.cancel() }
        server = NWConnection(host: host, port: port, using: NWParameters.udp)
        server?.stateUpdateHandler = {(newState) in self.stateUpdateHandler(newState: newState) }
        server?.start(queue: .main)

    }
    
    private func startTimer() {
        if !timer.isValid {
        timer = Timer.scheduledTimer(timeInterval: interval,
                                     target: self,
                                     selector: #selector(timerTic),
                                     userInfo: nil,
                                     repeats: true)
        }
    }
    
    @objc func timerTic() {
        switch commandToSend {
        case GET_TEMPERATURE:
            commandToSend = GET_TIME
        case GET_TIME:
            commandToSend = GET_LOG
        case GET_LOG:
            commandToSend = GET_LOG_INTERVAL
        case GET_LOG_INTERVAL:
            commandToSend = GET_HOSTNAME
        case GET_HOSTNAME:
            commandToSend = GET_TEMPERATURE
        default:
            commandToSend = GET_TEMPERATURE
        }
        
        self.sendCommand(server: self.server!, command: commandToSend)
        self.receiveReply(server: self.server!)
        
    }
    
    private func stateUpdateHandler(newState: NWConnection.State){
        switch (newState){
        case .setup:
            print("State: Setup.")
        case .waiting:
            print("State: Waiting.")
        case .ready:
            print("State: Ready.")
            startTimer()
            setTimeBtn.isEnabled = true
            //viewLogBtn.isEnabled = true
            saveLogBtn.isEnabled = true
            setLogIntervalBtn.isEnabled = true
            setTimeOnArduinoBtn.isEnabled = true
            setHostNameBtn.isEnabled = true
        case .failed:
            print("State: Failed.")
        case .cancelled:
            print("State: Cancelled.")
        default:
            print("State: Unknown state.")
        }
    }
    
    private func sendCommand(server: NWConnection, command: String) {
        server.send(content: command.data(using: String.Encoding.ascii),
                completion: .contentProcessed({error in
                     if let error = error {
                        print("error while sending data: \(error).")
                        return
                     }
                 }))
    }
    
    private func receiveReply(server: NWConnection){
        
        var logString = ""
        
        // completion handler receiveMessage not called if nothing received,
        // make sure to empty reply after valid receive
        server.receiveMessage (completion: {(content, context,   isComplete, error) in
            let replyLocal = String(decoding: content ?? Data(), as:   UTF8.self)
            reply = replyLocal
        })
        
        // Remove the command from te reply (= command + " " + value)
        let firstSpace = reply.firstIndex(of: " ") ?? reply.endIndex
        let result = reply[..<firstSpace]
        
        info.stringValue = "Connected."
        switch result {
        case GET_TEMPERATURE:
            self.temperatureOut.stringValue = reply.suffix(from: firstSpace) + " °C"
            reply = ""
        case GET_TIME:
            self.timeFromArduino.stringValue = "Time: " + String(reply.suffix(from: firstSpace))
            reply = ""
        case GET_LOG:
            let startOfString = reply.index(after: firstSpace)  //Remove space
            logString = String(reply.suffix(from: startOfString))
            log = decodeLog(log: logString)
            logTable.reloadData()
            reply = ""
        case GET_LOG_INTERVAL:
            logIntervalFromArduino.stringValue = "Log interval: " + String(reply.suffix(from: firstSpace))
            reply = ""
        case GET_HOSTNAME:
            hostNameFromArduino.stringValue = String(reply.suffix(from: firstSpace))
            reply = ""
        case MESSAGE_EMPTY:
            info.stringValue = "Waiting for sensor."
        default:
            print("Unknown command.")
        }
    }
    
    @IBAction func setTimeOnArduino(_ sender: NSButton) {
        let date = Date()
        let calender = Calendar.current
        let hour = calender.component(.hour, from: date)
        let minute = calender.component(.minute, from: date)
        
        //Stop timer so we can set the time
        timer.invalidate()
        
        // Send SET_TIME command
        let setTimeCommand = SET_TIME + String(format: " %02d:%02d",hour,minute)
        server!.send(content: setTimeCommand.data(using: String.Encoding.ascii),
                completion: .contentProcessed({error in
                     if let error = error {
                        print("error while sending data: \(error).")
                        return
                     }
                 }))
        // Wait for response
        timeFromArduino.stringValue = "Time: --:--:--"
        // Receive response
        server!.receiveMessage (completion: {(content, context,   isComplete, error) in
            print(String(decoding: content!, as:   UTF8.self))
        })
        
        // Continue
        startTimer()
    }
    
    @IBAction func logIntervalBtn(_ sender: NSButton) {
        //Stop timer so we can set the time
        timer.invalidate()
        
        // Waiting for response
        logIntervalFromArduino.stringValue = "Log interval: ---- s"
        
        // Send SET_TIME command
        let setTimeCommand = SET_LOG_INTERVAL + " " + logInterval.stringValue
        server!.send(content: setTimeCommand.data(using: String.Encoding.ascii),
                completion: .contentProcessed({error in
                     if let error = error {
                        print("error while sending data: \(error).")
                        return
                     }
                 }))
        // Receive response
        server!.receiveMessage (completion: {(content, context,   isComplete, error) in
            print(String(decoding: content!, as:   UTF8.self))
        })
        
        // Continue
        startTimer()
    }
    
    @IBAction func setHostnameOnArduino(_ sender: NSButton) {
        //Stop timer so we can set the time
        timer.invalidate()
        
        // Wait for response
        hostNameFromArduino.stringValue = "------"
        
        // Send SET_HOSTNAME command
        let setHostnameCommand = SET_HOSTNAME +  " " + hostNameForArduino.stringValue
        server!.send(content: setHostnameCommand.data(using: String.Encoding.ascii),
                completion: .contentProcessed({error in
                     if let error = error {
                        print("error while sending data: \(error).")
                        return
                     }
                 }))
 
        // Receive response
        server!.receiveMessage (completion: {(content, context,   isComplete, error) in
            print(String(decoding: content!, as:   UTF8.self))
        })
        // Continue
        startTimer()
    }
    
    /*
    @IBAction func viewLog(_ sender: NSButton) {
        print("View log")
        
        // Send GET_LOG command
        server!.send(content: GET_LOG.data(using: String.Encoding.ascii),
                     completion: .contentProcessed({error in
                        if let error = error {
                            print("error while sending data: \(error).")
                            return
                        }
                     }))
        // Receive response
        server!.receiveMessage (completion: {(content, context,   isComplete, error) in
            print(String(decoding: content!, as:   UTF8.self))
            let toSave = String(decoding: content!, as:   UTF8.self)
            let firstSpace = toSave.firstIndex(of: " ") ?? toSave.endIndex
            let index = toSave.index(after: firstSpace)
        })
    }*/
    @IBAction func saveLog(_ sender: NSButton) {

        //Stop timer so we can get the current log
        timer.invalidate()
        
        // Save log to ...
        let savePanel = NSSavePanel()
        var fileURL: URL? //(fileURLWithPath: "")
        var fileHandle: FileHandle?
        
        savePanel.title = "Save log."
        savePanel.nameFieldStringValue = "Temperature.log"
        switch savePanel.runModal() {
        case .OK:
            fileURL = savePanel.url!
        case .cancel:
            fileURL = nil
        default:
            print("NSOpenPanel: error")
            exit(0)
        }
                
        if (fileURL != nil) {
            fileHandle = FileHandle(forWritingAtPath: fileURL!.path)
            // Send GET_LOG command
            server!.send(content: GET_LOG.data(using: String.Encoding.ascii),
                         completion: .contentProcessed({error in
                            if let error = error {
                                print("error while sending data: \(error).")
                                return
                            }
                         }))
            // Receive response
            server!.receiveMessage (completion: {(content, context,   isComplete, error) in
                print(String(decoding: content!, as:   UTF8.self))
                let toSave = String(decoding: content!, as:   UTF8.self)
                let firstSpace = toSave.firstIndex(of: " ") ?? toSave.endIndex
                let index = toSave.index(after: firstSpace)
                // Write to file
                do {
                    //try String(decoding: content!, as:   UTF8.self).data(using: .ascii)?.write(to: fileURL!)
                    try String(toSave.suffix(from: index)).data(using: .ascii)?.write(to: fileURL!)
                }
                catch {
                    print("Error: func getLog: writing file")
                }
            })
        }
        
        // Continue
        startTimer()
    }
    
    private func decodeLog(log: String) -> [LogEntry] {
        var decoded = [LogEntry]()
        var toDecode = log
        var index = log.startIndex

        while index != toDecode.endIndex {
            index = toDecode.firstIndex(of: "\n") ?? toDecode.endIndex
            if index != toDecode.endIndex {
                //print(String(toDecode[...index]))
                let entry = decodeLogEntry(entry: String(toDecode[...index]))
                decoded.append(entry)
                toDecode = String(toDecode[toDecode.index(after: index)...])
            }

        }
        
        return decoded.reversed()
    }
    
    private func decodeLogEntry(entry: String) -> LogEntry {
        var remains = ""
        var temperature = ""
        //print(entry)
        var index = entry.firstIndex(of: "\t") ?? entry.endIndex
        var time = String(entry[..<index])
        if time == "99:99:99" { time = "--:--:--" }
        if index != entry.endIndex {
            index = entry.index(after: index)
            remains = String(entry[index...])
            index = remains.firstIndex(of: "\n") ?? entry.endIndex
            temperature = String(remains[..<index])
            if time ==  "--:--:--" { temperature = "--.--" }

        }
        else {
            temperature = "--.-"
        }
        return LogEntry(time: time, temperature: temperature)
    }
}

extension ViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return log.count
    }
}

extension ViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        var cellIdentifier: String = ""
        var text: String = ""
                
        if tableColumn == tableView.tableColumns[0] {
            text = log[row].time
            cellIdentifier = "Time"
            
        }
        
        if tableColumn == tableView.tableColumns[1] {
            text = log[row].temperature
            cellIdentifier = "Temperature"
        }
        
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(cellIdentifier), owner: nil)
            as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        return nil
    }
}

