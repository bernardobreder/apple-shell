//
//  Shell.swift
//  Shell
//
//  Created by Bernardo Breder on 10/12/16.
//
//

import Foundation

#if SWIFT_PACKAGE
#endif

public enum ShellError: Error {
    case fileNotExecutable(String)
    case outputNotUtf8
    case terminationStatus
    case fileOfCommandNotFound
    case error([String])
    case pipeBroken(Int32)
    case close
    case pipe
    case posix_spawn(Int32, [String])
    case exitStatus(Int32, [String])
    case exitSignal
    case waitpid(Int32)
}

open class Shell {
    
    public let executable: String
    
    public let arguments: [String]
    
    public init(_ executable: String, _ arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }
    
    open func start() throws -> ShellProcess {
        return try ShellProcess(shell: self)
    }
    
    open func startSystem() -> Bool {
        var arguments: [String] = []
        arguments.append(self.executable)
        for arg in self.arguments { arguments.append(arg) }
        do {
            try system(arguments)
            return true
        } catch {
            return false
        }
    }
    
}

open class ShellProcess {
    
    public let status: Int
    
    public let output: [String]
    
    public init(shell: Shell) throws {
        var pipe: [Int32] = [0, 0]
        defer {
            close(pipe[0])
            close(pipe[1])
        }
        let action = ShellInternalAction()
        #if os(Linux)
            guard Glibc.pipe(&pipe) == 0 else { throw ShellError.pipe }
        #else
            guard Darwin.pipe(&pipe) == 0 else { throw ShellError.pipe }
        #endif
        // Open /dev/null as stdin.
        action.addOpenStdInToDevNull()
        
        // Open the write end of the pipe as stdout (and stderr, if desired).
        posix_spawn_file_actions_adddup2(&action.action, pipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&action.action, pipe[1], STDERR_FILENO)
        
        // Close the other ends of the pipe.
        posix_spawn_file_actions_addclose(&action.action, pipe[0])
        posix_spawn_file_actions_addclose(&action.action, pipe[1])
        
        // Launch the command.
        var arguments: [String] = []
        arguments.append(shell.executable)
        for arg in shell.arguments { arguments.append(arg) }
        let pid = try posix_spawnp(arguments[0], args: arguments, environment: nil, action: action.action)
        
        guard close(pipe[1]) == 0 else { throw ShellError.close }
        
        // Read all of the data from the output pipe.
        let N = 4096
        var buf = [Int8](repeating: 0, count: N + 1)
        
        var out = ""
        loop: while true {
            let n = read(pipe[0], &buf, N)
            switch n {
            case  -1:
                if errno == EINTR { continue }
                else { throw ShellError.pipeBroken(errno) }
            case 0:
                break loop
            default:
                buf[n] = 0
                if let str = String(validatingUTF8: buf) { out += str }
                else { throw ShellError.outputNotUtf8 }
            }
        }
        close(pipe[0])
        status = try Int(waitpid(pid))
        output = out.trimmingCharacters(in: .whitespacesAndNewlines).characters.split(separator: "\n").map(String.init)
    }
    
    public var success: Bool {
        return status == 0
    }
    
    public var hasError: Bool {
        return status != 0
    }
    
    public var errorAllLines: String {
        return output.reduce("", {$0 + "\n" + $1}).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}

#if os(Linux)
    import Glibc
    typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t
#else
    import Darwin.C
    typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t?
#endif

fileprivate func posix_spawnp(_ path: String, args: [String], environment: [String: String]? = nil, action: swiftpm_posix_spawn_file_actions_t? = nil) throws -> pid_t {
    let argv: [UnsafeMutablePointer<CChar>?] = args.map{ $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    let environment = environment ?? ProcessInfo.processInfo.environment
    let env: [UnsafeMutablePointer<CChar>?] = environment.map{ "\($0.0)=\($0.1)".withCString(strdup) }
    defer { for case let arg? in env { free(arg) } }
    var pid = pid_t()
    let rv: Int32
    if var action = action {
        rv = posix_spawnp(&pid, argv[0], &action, nil, argv + [nil], env + [nil])
    } else {
        rv = posix_spawnp(&pid, argv[0], nil, nil, argv + [nil], env + [nil])
    }
    guard rv == 0 else { throw ShellError.posix_spawn(rv, args) }
    return pid
}

fileprivate func system(_ arguments: [String], environment: [String:String]? = nil) throws {
    let action = ShellInternalAction()
    action.addOpenStdOutToDevNull()
    let pid = try posix_spawnp(arguments[0], args: arguments, environment: environment, action: action.action)
    let exitStatus = try waitpid(pid)
    guard exitStatus == 0 else { throw ShellError.exitStatus(exitStatus, arguments) }
}

fileprivate func _WSTATUS(_ status: CInt) -> CInt {
    return status & 0x7f
}

fileprivate func WIFEXITED(_ status: CInt) -> Bool {
    return _WSTATUS(status) == 0
}

fileprivate func WEXITSTATUS(_ status: CInt) -> CInt {
    return (status >> 8) & 0xff
}

fileprivate func waitpid(_ pid: pid_t) throws -> Int32 {
    while true {
        var exitStatus: Int32 = 0
        let rv = waitpid(pid, &exitStatus, 0)
        if rv != -1 {
            if WIFEXITED(exitStatus) {
                return WEXITSTATUS(exitStatus)
            } else {
                throw ShellError.exitSignal
            }
        } else if errno == EINTR {
            continue
        } else {
            throw ShellError.waitpid(errno)
        }
    }
}

class ShellInternalAction {
    
    public var action: swiftpm_posix_spawn_file_actions_t
    
    init() {
        #if os(Linux)
            self.action = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&self.action)
    }
    
    deinit {
        posix_spawn_file_actions_destroy(&self.action)
    }
    
    public func addOpenStdOutToDevNull() {
        posix_spawn_file_actions_addopen(&self.action, STDOUT_FILENO, "/dev/null", O_RDONLY, 0)
    }
    
    public func addOpenStdInToDevNull() {
        posix_spawn_file_actions_addopen(&self.action, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
    }
    
}
