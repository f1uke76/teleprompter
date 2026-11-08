param(
  [int]$Seconds = 60,
  [string]$OutFile = "",
  [switch]$SelfTest
)

# ============================================================
#  系统级按键监听（Windows 底层键盘钩子 WH_KEYBOARD_LL）
#
#  为什么要这个：网页只能收到「浏览器看得见」的键。音量+ / 音量- /
#  静音 / 播放暂停 这类系统媒体键会被 Windows 先吃掉，网页里完全没反应。
#  这个脚本挂的是全局键盘钩子，任何窗口按的键都能抓到，包括媒体键，
#  并把「虚拟键码 VK + 扫描码」原样打出来。
#
#  用法：双击同目录的「按键监听-系统级.cmd」，然后依次按翻页器的 5 个按钮。
#        每个按钮按两下、中间停一秒，方便对照。
#        结果同时打印在窗口里、写进「按键记录.txt」。
# ============================================================

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = Join-Path $root '按键记录.txt' }

Add-Type -AssemblyName System.Windows.Forms | Out-Null

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Concurrent;
public class LLKeyHookPC {
  public struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public IntPtr dwExtraInfo; }
  public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);
  public static HookProc Proc;
  static IntPtr hook = IntPtr.Zero;
  public static ConcurrentQueue<string> Queue = new ConcurrentQueue<string>();
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
  [DllImport("user32.dll", SetLastError=true)] static extern bool UnhookWindowsHookEx(IntPtr hhk);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
  [DllImport("kernel32.dll", CharSet=CharSet.Auto)] public static extern IntPtr GetModuleHandle(string n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public static IntPtr Install(){
    Proc = new HookProc(Callback);
    hook = SetWindowsHookEx(13, Proc, GetModuleHandle(null), 0);
    return hook;
  }
  public static int LastErr(){ return Marshal.GetLastWin32Error(); }
  public static void Uninstall(){ if(hook!=IntPtr.Zero){ UnhookWindowsHookEx(hook); hook=IntPtr.Zero; } }
  static IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam){
    if(nCode>=0){
      KBDLLHOOKSTRUCT info = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
      int wm = wParam.ToInt32();
      string type = (wm==0x100 || wm==0x104) ? "down" : "up";
      bool ext = (info.flags & 0x01) != 0;
      Queue.Enqueue(info.vkCode.ToString() + "|" + info.scanCode.ToString() + "|" + type + "|" + (ext ? "ext" : "-"));
    }
    return CallNextHookEx(hook, nCode, wParam, lParam);
  }
}
'@
Add-Type -TypeDefinition $src

$handle = [LLKeyHookPC]::Install()
if ($handle -eq [IntPtr]::Zero) {
  Write-Host ''
  Write-Host ('  [x] 安装键盘钩子失败（错误码 ' + [LLKeyHookPC]::LastErr() + '）') -ForegroundColor Red
  Write-Host '      可以试试右键「以管理员身份运行」这个 cmd。'
  Read-Host '按回车退出'
  exit 1
}

function Get-VkName([int]$vk) {
  $names = @{
    8='Backspace 退格';9='Tab';13='Enter 回车';16='Shift';17='Ctrl';18='Alt';19='Pause 暂停';
    20='CapsLock';27='Esc';32='空格 Space';
    33='PageUp（上一页/上一张）';34='PageDown（下一页/下一张）';35='End';36='Home';
    37='ArrowLeft（左）';38='ArrowUp（上）';39='ArrowRight（右）';40='ArrowDown（下）';
    45='Insert';46='Delete 删除';
    48='0';49='1';50='2';51='3';52='4';53='5';54='6';55='7';56='8';57='9';
    65='A';66='B（常见黑屏键）';67='C';68='D';69='E';70='F';71='G';72='H';73='I';74='J';75='K';76='L';77='M';
    78='N';79='O';80='P';81='Q';82='R';83='S';84='T';85='U';86='V';87='W';88='X';89='Y';90='Z';
    96='小键盘0';97='小键盘1';98='小键盘2';99='小键盘3';100='小键盘4';
    101='小键盘5';102='小键盘6';103='小键盘7';104='小键盘8';105='小键盘9';
    106='小键盘 *';107='小键盘 +';109='小键盘 -';110='小键盘 .';111='小键盘 /';
    112='F1';113='F2';114='F3';115='F4';116='F5（常见全屏键）';117='F6';118='F7';119='F8';
    120='F9';121='F10';122='F11';123='F12';
    144='NumLock';145='ScrollLock';186=';';187='=';188=',';189='-';190='.';191='/';192='`';
    219='[';220='\';221=']';222="'";
    173='静音（系统媒体键）';174='音量-（系统媒体键）';175='音量+（系统媒体键）';
    176='下一曲（媒体键）';177='上一曲（媒体键）';178='停止（媒体键）';179='播放/暂停（媒体键）';
    180='主页（媒体键）';181='刷新（媒体键）';182='计算器（媒体键）';
    166='浏览器后退';167='浏览器前进';168='浏览器刷新';169='浏览器主页';170='浏览器搜索';171='浏览器收藏'
  }
  if ($names.ContainsKey($vk)) { return $names[$vk] }
  return ''
}

$lines = New-Object System.Collections.Generic.List[string]
$start = Get-Date
$lines.Add('# 按键记录   开始 ' + $start.ToString('yyyy-MM-dd HH:mm:ss'))
$lines.Add('# 虚键码 VK   扫描码   动作   扩展键   说明')

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host (' 按键监听已开始，共 ' + $Seconds + ' 秒') -ForegroundColor Green
Write-Host ' 现在请依次按下翻页器上的 5 个按钮（每个可以按两下，中间停一秒）' -ForegroundColor Green
Write-Host ' 这里抓的是全局按键，窗口不用保持在最前面；但别让焦点落在管理员程序上'
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.WindowState = 'Minimized'
$form.Opacity = 0
$form.Show()
[System.Windows.Forms.Application]::DoEvents()

$deadline = (Get-Date).AddSeconds($Seconds)
$sentSelfTest = $false
while ((Get-Date) -lt $deadline) {
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 40

  if ($SelfTest -and -not $sentSelfTest) {
    $sentSelfTest = $true
    foreach ($vk in @(33, 34, 175, 174, 116)) {
      [LLKeyHookPC]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds 60
      [LLKeyHookPC]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds 120
    }
  }

  $item = ''
  while ([LLKeyHookPC]::Queue.TryDequeue([ref]$item)) {
    $p = $item.Split('|')
    $vk = [int]$p[0]
    $t = ((Get-Date) - $start).TotalSeconds
    $line = ('{0,6:N2}s   VK {1,3} (0x{1:X2})   扫描码 {2,3}   {3,-4}   {4}   {5}' -f $t, $vk, [int]$p[1], $p[2], $p[3], (Get-VkName $vk))
    $lines.Add($line)
    Write-Host $line
  }
}
$form.Close()
[LLKeyHookPC]::Uninstall()

# 去重汇总
$seen = @{}
$order = New-Object System.Collections.Generic.List[int]
foreach ($l in $lines) {
  if ($l -match 'VK\s+(\d+)') {
    $k = [int]$matches[1]
    if (-not $seen.ContainsKey($k)) { $seen[$k] = 0; $order.Add($k) }
    $seen[$k]++
  }
}
$lines.Add('')
$lines.Add('# ===== 去重汇总（按第一次出现的顺序） =====')
foreach ($k in $order) {
  $lines.Add(('VK {0,3} (0x{0:X2})  次数 {1,2}  {2}' -f $k, $seen[$k], (Get-VkName $k)))
}

$lines | Set-Content -Path $OutFile -Encoding UTF8

Write-Host ''
Write-Host ('  共抓到 ' + $order.Count + ' 种键，记录已保存：' + $OutFile) -ForegroundColor Green
if ($order.Count -eq 0) {
  Write-Host '  一个键都没抓到：确认脚本窗口已出现、翻页器已连上，再重试一次。' -ForegroundColor Yellow
} else {
  Write-Host '  去重汇总：' -ForegroundColor Green
  foreach ($k in $order) {
    $nm = Get-VkName $k
    Write-Host ('    VK {0,3} (0x{0:X2})  {1,2} 次   {2}' -f $k, $seen[$k], $nm)
  }
}
if (-not $SelfTest) { Read-Host '按回车关闭窗口' }
