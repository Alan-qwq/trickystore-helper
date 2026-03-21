#TrickyStore 辅助脚本

本脚本是一个TrickyStore模块的辅助shell脚本，支持获取有效Keybox文件、一键更新target.txt、以及配置prop属性隐藏脚本等，以帮助通过环境检测

#功能特性
1.Keybox更新
支持从三个不同源下载并自动解码keybox.xml文件：
（1）Yurikey 源
（2）Tricky-Addon-Update-Target-List 源
（3）IntegrityBox 源

2.一键更新target.txt
自动获取所需包名，并可根据需求选择添加 ! 或 ? 后缀，生成target.txt文件。

3.一键配置TrickyStore
安装TrickyStore后运行本脚本
无需安装任何其他的TrickyStore辅助模块
自动完成以下三项核心配置：
（1）配置/data/adb/tricky_store/system_app
（2）生成开机自启的prop属性修改脚本，屏蔽Bootloader解锁状态、修改导致环境泄露的相关属性
（3）更新target.txt

#运行要求
已Root设备
1.含有Busybox/toybox 环境
2.支持curl或wget
3.已正确安装TrickyStore模块
