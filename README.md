##TrickyStore 辅助脚本

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
自动完成以下配置：
（1）生成开机自启的prop属性修改脚本，隐藏导致环境泄露的相关属性
（2）更新target.txt

借鉴和使用了Tricky Addon-Update Target List的代码
