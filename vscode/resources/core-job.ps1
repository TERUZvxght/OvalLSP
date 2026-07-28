param(
  [Parameter(Mandatory = $true)]
  [string]$ChildCommand,
  [Parameter(Mandatory = $true)]
  [string]$ChildArguments
)

$nativeSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class OvalLspJob {
  [StructLayout(LayoutKind.Sequential)]
  private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
    public long PerProcessUserTimeLimit;
    public long PerJobUserTimeLimit;
    public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize;
    public UIntPtr MaximumWorkingSetSize;
    public uint ActiveProcessLimit;
    public UIntPtr Affinity;
    public uint PriorityClass;
    public uint SchedulingClass;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct IO_COUNTERS {
    public ulong ReadOperationCount;
    public ulong WriteOperationCount;
    public ulong OtherOperationCount;
    public ulong ReadTransferCount;
    public ulong WriteTransferCount;
    public ulong OtherTransferCount;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
    public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
    public IO_COUNTERS IoInfo;
    public UIntPtr ProcessMemoryLimit;
    public UIntPtr JobMemoryLimit;
    public UIntPtr PeakProcessMemoryUsed;
    public UIntPtr PeakJobMemoryUsed;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct STARTUPINFO {
    public uint cb;
    public string lpReserved;
    public string lpDesktop;
    public string lpTitle;
    public uint dwX;
    public uint dwY;
    public uint dwXSize;
    public uint dwYSize;
    public uint dwXCountChars;
    public uint dwYCountChars;
    public uint dwFillAttribute;
    public uint dwFlags;
    public ushort wShowWindow;
    public ushort cbReserved2;
    public IntPtr lpReserved2;
    public IntPtr hStdInput;
    public IntPtr hStdOutput;
    public IntPtr hStdError;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct PROCESS_INFORMATION {
    public IntPtr hProcess;
    public IntPtr hThread;
    public uint dwProcessId;
    public uint dwThreadId;
  }

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
  private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

  [DllImport("kernel32.dll")]
  private static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);

  [DllImport("kernel32.dll")]
  private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern bool CreateProcess(
    string applicationName, StringBuilder commandLine, IntPtr processAttributes, IntPtr threadAttributes,
    bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory,
    ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInformation
  );

  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern uint ResumeThread(IntPtr thread);

  [DllImport("kernel32.dll")]
  private static extern IntPtr GetStdHandle(int standardHandle);

  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

  [DllImport("kernel32.dll")]
  private static extern bool TerminateProcess(IntPtr process, uint exitCode);

  [DllImport("kernel32.dll")]
  private static extern bool CloseHandle(IntPtr handle);

  public static int Run(string command, string arguments) {
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
    const int JobObjectExtendedLimitInformation = 9;
    const uint CREATE_SUSPENDED = 0x00000004;
    const uint STARTF_USESTDHANDLES = 0x00000100;
    const uint INFINITE = 0xFFFFFFFF;
    const uint WAIT_FAILED = 0xFFFFFFFF;

    IntPtr job = CreateJobObject(IntPtr.Zero, null);
    if (job == IntPtr.Zero) {
      throw new Win32Exception();
    }

    PROCESS_INFORMATION process = new PROCESS_INFORMATION();
    bool created = false;
    bool assigned = false;
    try {
      var limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
      limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      int size = Marshal.SizeOf(limits);
      IntPtr pointer = Marshal.AllocHGlobal(size);
      try {
        Marshal.StructureToPtr(limits, pointer, false);
        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, pointer, (uint)size)) {
          throw new Win32Exception();
        }
      } finally {
        Marshal.FreeHGlobal(pointer);
      }

      var startup = new STARTUPINFO();
      startup.cb = (uint)Marshal.SizeOf(startup);
      startup.dwFlags = STARTF_USESTDHANDLES;
      startup.hStdInput = GetStdHandle(-10);
      startup.hStdOutput = GetStdHandle(-11);
      startup.hStdError = GetStdHandle(-12);
      var commandLine = new StringBuilder(Quote(command) + (String.IsNullOrEmpty(arguments) ? "" : " " + arguments));

      // lpApplicationName is deliberately null: with a non-null value
      // CreateProcess does NOT search PATH and does NOT append ".exe".
      // `ovallsp.ruby.command` / `ovallsp.rubyExecutablePath` are
      // documented as user-settable to a bare name, and rubyResolver
      // falls back to a bare "ruby", so passing the command there
      // regressed every such configuration relative to v0.1.4's Node
      // `spawn`. The command line below already carries the quoted
      // executable as argv[0], which is what drives resolution when
      // lpApplicationName is null.
      //
      // Note this does NOT make a .cmd/.bat shim launchable --
      // CreateProcess cannot execute batch files with either value; that
      // needs an explicit `cmd.exe /c`. Windows is not a supported
      // target for this Preview, so that gap is left as-is rather than
      // speculatively handled.
      if (!CreateProcess(null, commandLine, IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED,
                         IntPtr.Zero, null, ref startup, out process)) {
        throw new Win32Exception();
      }
      created = true;
      if (!AssignProcessToJobObject(job, process.hProcess)) {
        throw new Win32Exception();
      }
      assigned = true;
      if (ResumeThread(process.hThread) == UInt32.MaxValue) {
        throw new Win32Exception();
      }
      if (WaitForSingleObject(process.hProcess, INFINITE) == WAIT_FAILED) {
        throw new Win32Exception();
      }
      uint exitCode;
      if (!GetExitCodeProcess(process.hProcess, out exitCode)) {
        throw new Win32Exception();
      }
      return unchecked((int)exitCode);
    } finally {
      if (created && !assigned) {
        TerminateProcess(process.hProcess, 1);
      }
      if (process.hThread != IntPtr.Zero) {
        CloseHandle(process.hThread);
      }
      if (process.hProcess != IntPtr.Zero) {
        CloseHandle(process.hProcess);
      }
      CloseHandle(job);
    }
  }

  private static string Quote(string value) {
    return "\"" + value.Replace("\"", "\\\"") + "\"";
  }
}
'@

Add-Type -TypeDefinition $nativeSource -Language CSharp
exit ([OvalLspJob]::Run($ChildCommand, $ChildArguments))
