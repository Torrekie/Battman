---
title: 充电限制
---

# 充电限制

**充电限制**页面用于配置一个实验性的后台守护进程，使电池电量保持在指定区间内。

## 核心概念

- **限制电量**  
  设定电池充到多少百分比时停止充电。
- **恢复电量**  
  （可选）设定在低于该百分比后重新允许充电。
- **放电模式**  
  决定在放电阶段是保留外部供电，还是阻断外部供电而强制使用电池。
- **覆盖优化电池充电**  
  在 Battman 接管充电逻辑时，可选择是否覆盖系统的“优化电池充电”行为。

## 工作状态

- **允许充电** — 值守进程运行中，允许电量继续上升至预设上限。

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_continue.PNG" alt="Allowing charge badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **阻断充电** — 值守进程运行中，在抵达上限时保持不再充电。

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_stop.PNG" alt="Stopping charge badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **无外部电源** — 未检测到适配器，无法执行限制。

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_noext.PNG" alt="No external power badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **有适配器但无供电** — 连接了适配器但未输出电流（如线材 / 协议问题或计划任务）。

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_nopwr.PNG" alt="No current badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **优化电池充电接管** — 在未覆盖“优化电池充电”的软模式下，系统“优化电池充电”可能忽略 Battman 的请求。需要 Battman 优先时，请先启用“循环时覆盖‘优化电池充电’”再启动值守进程。

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_obc.PNG" alt="OBC badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

## 风险提示

- 此功能仍在测试阶段，可能无法在所有设备上正常工作。
- 此功能会直接写入系统电源相关接口，并长时间运行后台代码。
- 当前 Battman 值守进程作为常规后台进程运行，未使用系统 `LaunchDaemons`。设备重启或执行 ldrestart 后需要手动重新启动值守进程才能生效。
