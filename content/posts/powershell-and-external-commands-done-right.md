---
title: "PowerShell and external commands done right"
lastmod: '2013-12-22'
date: "2010-06-17"
---

Windows PowerShell is a massive step up from the VBScript horror used to manage Windows systems (I have no idea how people wrote websites with it without going mental). One of the things that annoyed me to no end though was how there seemed to be black magic involved when trying to make PowerShell execute external commands, i.e. not PowerShell cmdlets.

It is actually quite straight-forward once you wrap your head around it - it's just that we try to do things the way we did in VBScript or in OO languages, and PowerShell doesn't like that.

# Background

I'm currently writing a script to automate creating and deleting volume shadow copies, creating a ShadowProtect image in between.

This includes normal looking commands like,

```bat
H:\backup\scripts\vshadow.exe -p -script="H:\backup\scripts\vss.cmd" E: M: P:
```

As well as funny looking ShadowProtect commands,

```bat
H:\backup\scripts\sbrun.exe  -mdn ( sbvol -f  \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy43 \\?\E: : sbcrypt -50 : sbfile -wd H:\backup\backups )
```

# The wrong way to do it

If you ask Google, you'll probably get responses telling you to do this:

```powershell
$exe = "H:\backup\scripts\vshadow.exe"
$arguments = '-p -script="H:\backup\scripts\vss.cmd" E: M: P:'
$proc = [Diagnostics.Process]::Start($exe, $arguments)
$proc.WaitForExit()
```

This works, but it isn't the right way to going about mainly because it isn't the PowerShell way. You're actually calling the class in the .NET Framework (which PowerShell is based on) that application developers use to launch external applications. Not only is this more code, but also makes it a bit more complicated if you want to process the standard output/error, and also results in a new command window popping up even if it is just another command line application. This method has gained a bit more legitimacy in some use cases though, and in PowerShell v2, is now accessible using the [Start-Process](http://technet.microsoft.com/en-us/library/hh849848.aspx) cmdlet.

The next most popular way, but also somewhat error prone and hence the most frustrating, is this:

```powershell
$exe = "H:\backup\scripts\vshadow.exe"
$arguments = "-p -script=`"H:\backup\scripts\vss.cmd`" E: M: P:"
&$exe $arguments
```

The ampersand (`&`) here tells PowerShell to execute that command, instead of treating it as a cmdlet or a string. The backticks (the funny looking single-quotes) are there to escape the following character, similar to the `\"` in C-based languages, or double-double-quotes (`""`) in VB. Otherwise the `"` character will end the string and the parser will cry when it can't understand what you're trying to say after that. (You can alternatively use single-quotes instead in this case, as I have in the previous example.)

The reason why this doesn't work is because PowerShell is a shell first and foremost. What PowerShell is actually doing is executing the specified executable, but then passes all your parameters *within quotes* (or if it makes more sense, as a single parameter), as you can see in this alternate, more concise version:

```powershell
& "H:\backup\scripts\vshadow.exe" "-p -script=`"H:\backup\scripts\vss.cmd`" E: M: P:"
```

You'll probably spend hours pulling your hair out wondering why things aren't working even when the arguments seem to be passed ok (to make things worse, some command line apps work fine with it). You'll also likely get cryptic error messages like,

```text
Invalid parameter: "-p -script=`"H:\backup\scripts\vss.cmd`" E: M: P:"
```

And you'll be left wondering why the hell that is invalid.

# Enter echoargs.exe

Echoargs is a simple tool that spits out the arguments it receives. It is part of the [PowerShell Community Extensions](http://pscx.codeplex.com/) download.

If you replaced the executable in the above command with `echoargs.exe`, you'll be able to see what's happening.

```powershell
& "H:\backup\scripts\echoargs.exe" "-p -script=`"H:\backup\scripts\vss.cmd`" E: M: P:"
```

Execute that and you'll get the following output,

```text
Arg 0 is <-p -script=H:\backup\scripts\vss.cmd E: M: P:>
```

See how all the parameters are being interpreted as one string? That is not what you want - you want them to be interpreted as separate arguments.

# How to do it the PowerShell way

Remember that PowerShell is a shell first and foremost. To run the above external command, just do the following:

```powershell
$exe = "H:\backup\scripts\vshadow.exe"
&$exe -p -script=H:\backup\scripts\vss.cmd E: M: P:
```

Notice that I'm not putting all the arguments into a single string, I'm just writing them as they are. If you run this with Echoargs, you'll get the following:

```text
Arg 0 is <-p>
Arg 1 is <-script=H:\backup\scripts\vss.cmd>
Arg 2 is <E:>
Arg 3 is <M:>
Arg 4 is <P:>
```

That is what the command line application expects. Notice that each parameter is considered a different argument, as opposed to a single string for all parameters.

# Using PowerShell v3 or later?

If you're using PowerShell v3 (which shipped with Windows 8 and Windows Server 2012 and is also available for Windows 7 / 2008 as a separate download), there is a new language feature that simplifies a lot of this. Instead of having to stuff around with escaping and quoting parameters to dodge the PowerShell parser, you can now use the `--%` operator which tells PowerShell to stop parsing from that point onward until the end of the line. Everything from that operator onwards is parsed by the ~~Windows Command Processor (cmd.exe)~~ parser used by the program (e.g. MS C/C++ runtime) and _all those rules apply instead_. This means that you can't reference any PowerShell variables after that operator (any references will be past literally, i.e. `$dir` will be passed to the external command as `$dir`), but it also means you can reference _environment variables_ using the cmd.exe syntax, e.g. `%USERPROFILE%` (I have no idea what expands them; is cmd.exe still involved somehow?).

For example, the following command (which will work only in cmd.exe and not PowerShell in its current form),

```bat
H:\backup\scripts\sbrun.exe -mdn ( sbvol -f  \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy43 \\?\E: : sbcrypt -50 : sbfile -wd H:\backup\backups )
```

can be written as,

```powershell
&"H:\backup\scripts\sbrun.exe" --% -mdn ( sbvol -f  \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy43 \\?\E: : sbcrypt -50 : sbfile -wd H:\backup\backups )
```

for execution within PowerShell - there is no need to bother with escaping the brackets.

_Remember that this only exists in PowerShell v3 or later so if your scripts target older versions of PowerShell, you cannot use this. Also, if you need to reference PowerShell variables, you can't use this trick either. Read on._

# What about parameters with spaces in them?

Now, you might be asking, how do I send parameters that contain spaces? Normally we would quote the part that has spaces, e.g.

```powershell
&$exe -p -script="H:\backup\scripts temp\vss.cmd" E: M: P:
```
But not in Powershell. That will simply confuse it. Instead, just place the entire parameter in quotes, e.g.

```powershell
&$exe -p "-script=H:\backup\scripts temp\vss.cmd" E: M: P:
```

# Or parameters where the quote characters need to passed on?

If it is necessary for the quotes to be passed on to the external command (it very rarely is), you will need to double-escape the quotes inside the string, once for PowerShell using the backtick character (\`), and again for the ~~Windows Command Processor~~ parser using the backslash character (`\`). For example,

```powershell
&$exe -p "-script=\`"H:\backup\scripts temp\vss.cmd\`"" E: M: P:
```

When you execute an external command, Powershell grabs the command and the arguments (after the strings have been processed by Powershell and the Powershell escape characters removed), then passes it as a single string to the ~~Windows Command Processor (or possibly straight to the Windows Shell/ Win32 API)~~ program for execution. The ~~Windows Command Processor~~ program, depending on the parser used (e.g. MS C/C++ runtime), has a separate set of rules for escaping things, therefore it is necessary to escape again to prevent it from interpreting the quotes. Most (but annoyingly, not all) use the MS C/C++ runtime parser, and from what I can gather, it splits up the string into arguments by splitting at each space, unless the space is inside quotes. Because the inner quotes were not escaped using the ~~Windows Command Processor~~ parser escape character (the backslash), the ~~command processor~~ parser interpreted them as if the quoted parts contained "-script=" and "", therefore the space between `scripts` and `temp` isn't actually within any quotes and hence split.

You can see this happening by playing with echoargs.exe (which uses the MS C/C++ runtime parser) inside the Command Prompt (not the PowerShell prompt).

_The order of the escape characters is important - it must be the backslash character first, then the backtick character. Otherwise, because PowerShell processes the command first, the backtick will escape the backslash instead of the quote as intended._

If the program does not use the MS C/C++ runtime parser to parse command line arguments, then how it is parsed is entirely dependent on how the program implemented it. The following is a quick PowerShell script that shows you what the raw command line is being passed to the program as well as how one of the alternate methods of parsing it works (CommandLineToArgvW - I believe this is _not_ what the MS C/C++ runtime uses).

```powershell
$Kernel32Definition = @'
[DllImport("kernel32")]
public static extern IntPtr GetCommandLineW();
[DllImport("kernel32")]
public static extern IntPtr LocalFree(IntPtr hMem);
'@

$Kernel32 = Add-Type -MemberDefinition $Kernel32Definition -Name 'Kernel32' -Namespace 'Win32' -PassThru

$Shell32Definition = @'
[DllImport("shell32.dll", SetLastError = true)]
public static extern IntPtr CommandLineToArgvW(
    [MarshalAs(UnmanagedType.LPWStr)] string lpCmdLine,
    out int pNumArgs);
'@

$Shell32 = Add-Type -MemberDefinition $Shell32Definition -Name 'Shell32' -Namespace 'Win32' -PassThru

$RawCommandLine = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Kernel32::GetCommandLineW())
Write-Host "The raw command line is (excluding the angle brackets)\:`n<$RawCommandLine>`n"

$ParsedArgCount = 0
$ParsedArgsPtr = $Shell32::CommandLineToArgvW($RawCommandLine, [ref] $ParsedArgCount)

try
{
    $ParsedArgs = @( );

    0..$ParsedArgCount | ForEach-Object {
        $ParsedArgs += [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
            [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ParsedArgsPtr, $_ * [IntPtr]::Size)
        )
    }
}
finally
{
    $Kernel32::LocalFree($ParsedArgsPtr) | Out-Null
}

Write-Host "The command line as parsed by CommandLineToArgvW (not MSVCRT) is:"
# -lt to skip the last item, which is a NULL ptr
for ($i = 0; $i -lt $ParsedArgCount; $i += 1) {
    Write-Host "argv[$i] <$($ParsedArgs[$i])>"
}
```

Save the above script to a file, e.g. `GetCommandLine.ps1`, and execute it like so -

```powershell
PS C:\Users\User\Desktop> powershell .\GetCommandLine.ps1 a b"c d"e f
The raw command line is (excluding the angle brackets)\:
<"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"  .\GetCommandLine.ps1 a "bc de" f>

The command line as parsed by CommandLineToArgvW (not MSVCRT) is:
argv[0] <C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe>
argv[1] <.\GetCommandLine.ps1>
argv[2] <a>
argv[3] <bc de>
argv[4] <f>
```

_It is important to execute it in a separate instance of PowerShell (hence the 'powershell' in the command line). Otherwise, it will simply show you the arguments of the current instance of PowerShell when it was launched._ Use the output of the raw command line to see what PowerShell is passing to the program you're running, i.e. after any parsing and manipulating that PowerShell does. In this example, notice how the position of the quote characters have changed between the original command line and the raw command line as printed by the script - this is PowerShell manipulating the strings (I'm not quite sure what it is doing though; looks like string concatenation for adjacent strings, but not sure why the quote character has moved).

For more on the bizarre and inconsistent world of Windows command argument parsing, see http://www.daviddeley.com/autohotkey/parameters/parameters.htm#WINARGV and https://gist.github.com/dolmen/6030690/raw/5dde469149420f12acd6f5a6120c3a90474e4088/ref.md.

# And parameters with dynamic/calculated values?

Remember the [variable expansion rules in PowerShell](http://blogs.msdn.com/b/powershell/archive/2006/07/15/variable-expansion-in-strings-and-herestrings.aspx). Enclose strings inside double-quotes, and variables inside will be expanded, e.g.

```powershell
$scriptsTempPath = "H:\backup\scripts temp"
&$exe -p "-script=$scriptsTempPath\vss.cmd" E: M: P:
```

Because variable expansion only works if strings are enclosed inside double-quotes, *double-quotes are required, regardless if whether or not there are spaces in the parameter*. You can have as many variables as you want inside each parameter.

# Or a variable containing a single parameter?
```powershell
$scriptsParameter = "-script=H:\backup\scripts temp\vss.cmd"
&$exe -p $scriptsParameter E: M: P:
```

No double-quotes are required here because the variable is surrounded by whitespace, so PowerShell will automatically expand the variable into a parameter. Using double-quotes won't break anything though; they are just redundant.

# But what if I want to build the arguments to pass in my script?

You need to know a PowerShell secret. If you specify an array of values, it will automatically expand them into separate parameters. For example,

```powershell
$drivesToBackup = @( ) # new empty array
$drivesToBackup += "E:" # always backup E drive

# only backup C drive on the first of each month
if ((Get-Date -Format dd) -eq 1) {
    $drivesToBackup += "C:"
}

&$exe -p "-script=H:\backup\scripts\vss.cmd" $drivesToBackup
```

If today was the first of the month, and if you run echoargs.exe you'll get the following output:

```text
Arg 0 is <-p>
Arg 1 is <-script=H:\backup\scripts\vss.cmd>
Arg 2 is <E:>
Arg 3 is <C:>
```

All of the above tricks work fine with command line apps that use the forward-slash (`/`) to denote the start of a parameter too (instead of a dash/hyphen), e.g.

```powershell
&$exe /p "/script=H:\backup\scripts\vss.cmd" E: M:
```

# But it still doesn't work!?!!!

Sometimes you run into command line apps that use non-standard notation (not that there ever was much of a defined standard). Something like this for example (this is a command line from scripting ShadowProtect),

```powershell
&"H:\backup\scripts\sbrun.exe"  -mdn ( sbvol -f  \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy43 \\?\E: : sbcrypt -50 : sbfile -wd H:\backup\backups )
```

If we run this using the tricks above, or even with echoargs.exe, you'll get PowerShell errors. This is because the parentheses in PowerShell denote code that should be executed and the result inserted in place of the parentheses. So in the above code, PowerShell is trying to find a cmdlet named sbvol, or an executable named sbvol in PATH. It fails because no such command exists by default.

To stop PowerShell from interpreting the parentheses and just pass them on instead, simple enclose them in quotes, e.g.

```powershell
&"H:\backup\scripts\sbrun.exe"  -mdn "(" sbvol -f  \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy43 \\?\E: : sbcrypt -50 : sbfile -wd H:\backup\backups ")"
```

Using the curly brackets, or braces, will also trip up Powershell. If you need to pass the brace characters (`{` or `}`) to an external command, they will need to be enclosed in quotes, otherwise you'll get cryptic parameters passed to your external command app, e.g.

```powershell
PS C:\Users\Sam> .\echoargs.exe { hello }
Arg 0 is <-encodedCommand>
Arg 1 is <IABoAGUAbABsAG8AIAA=>
Arg 2 is <-inputFormat>
Arg 3 is <xml>
Arg 4 is <-outputFormat>
Arg 5 is <text>

PS C:\Users\Sam> .\echoargs.exe "{" hello "}"
Arg 0 is <{>
Arg 1 is <hello>
Arg 2 is <}>
```

What's actually happening is that PowerShell considers the contents of the braces to be a script block, which are often used with cmdlets such as `Where-Object` or `ForEach-Object`.

The square brackets (`[` and `]`) also have special meaning in PowerShell ([globbing](http://msdn.microsoft.com/en-us/library/aa717088(VS.85).aspx)), but generally won't be interpreted as anything special when you're executing external commands; only certain cmdlets trigger the globbing behaviour, e.g. `Get-ChildItem`. So using them without enclosing them in quotes is fine.

Also remember the character that triggers PowerShell's variable expansion, the dollar sign (`$`). It should be escaped using a backtick if it is to be passed to the external executable. PowerShell is actually quite specific when it comes to parsing the `$` sign, but it is often safer to escape just in case.  If in doubt, try using single-quotes instead (variable expansion does not happen with single-quoted strings).

# Other bits of useful info

To refer to the current directory, use the dot, e.g.

```powershell
&".\echoargs.exe"
```

Note that the current directory may not necessarily be the directory the script is running from - it is dependent on the 'working directory' when executing the script, and also if you do any `cd` or `Set-Location` commands.

To get the script directory, include the following line within the script file, in the script scope (i.e. not within a function or some other script block). [Source](http://blogs.msdn.com/b/powershell/archive/2007/06/19/get-scriptdirectory.aspx).

```powershell
$scriptDirectory = Split-Path ($MyInvocation.MyCommand.Path) -Parent
```

Lastly, if you want to send the output of the command line app to the screen, and you're running that inside a function, pipe the command to Out-Host to force it to the screen, e.g.

```powershell
&$exe -p "-script=H:\backup\scripts temp\vss.cmd" E: M: P: | Out-Host
```

And if you want PowerShell to wait until that external process has finished before proceeding (but you don't want the output going anywhere), use `Out-Null`, e.g.

```powershell
&$exe -p "-script=H:\backup\scripts temp\vss.cmd" E: M: P: | Out-Null
```

If you did want the output you can either pipe it to `Out-Host` instead to show it on the screen or if you want it in a variable, you can pipe it to the `Tee-Object` cmdlet first, like this —

```powershell
&$exe -p "-script=H:\backup\scripts temp\vss.cmd" E: M: P: | Tee-Object -Variable scriptOutput | Out-Null
```

The output can then be accessed using the `scriptOutput` variable, e.g.

```powershell
echo $scriptOutput
```

When the output of a command is piped to another cmdlet, PowerShell has to stop and wait for the initial command and the cmdlets the output has been piped into to complete before continuing.
