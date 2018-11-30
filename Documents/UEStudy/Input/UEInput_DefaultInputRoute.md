# UE's default input routine.

虚幻的输入处理大致流程如下：

- InputXXXX 的消息并不直接使用，而是通知给 PlayerInput
	- 主要是记录到 PlayerInput 的各种 Key 的 KeyState 的 EventAccumulator 里面
    - **唯一特殊的是 ComponentClick 机制的处理**
        - 在 KeyDown/KeyUp 的时候，如果是 Click 机制，则判断一下是否能够触发 Click 。
        - 这个机制下直接发布 Click 消息给 Component 
        - *Consume 似乎不会被触发，也就是此时 LBDown/LBUp还是会继续处理*
- 下个 Tick 的时候才会实际做出 Input 的消息处理
	- 先走 PlayerInput 的 Tick 来处理各个 Axis 临时记录的初始化，以及手势分析
	- **然后是 Hit 分析，也就是 Hover 之类的分析**
		- 分析结果直接通知目标，没有PC自己的回调
			- 要是做翻牌这类的可能会很舒服
			- 但是要是做火球术攻击目标这类的，可能会比较绕
	- **然后是真正的 ProcessPlayerInput ，这个是可以 Override 的**
		- **BuildInputStack ，排序各 InputComponent**
			- **Pawn 最后， Pawn 会寻找多个，也就是可以往里安插其它 InputComponent**
			- Level 的输入其次
			- 然后是 CurrentInputStack
				- AActor 的 EnableInput
				- **UserWidget 的 InitializeInputComponent** ，——注意这个地方， UserWidget 作为U类，内涵 InputComponent 的做法。
					- 看了一下，UMG 的 Input Component 主要用来截获 Actions ，感觉很打补丁的做法。
					- 但是这个 Action 的机制倒是可以考虑，子类截获消息时候可能可以采取类似的范式。
				- 一些 Debug、Spectator 的特殊 InputComponent 。
		- **调用 PlayerInput 的 ProcessInputStack**
			- 先PC的 PreProcessInput
			- 直接取出 InputComponent 的各种 Action 设置去做处理，处理完毕后直接调用里面配置的 Delegate （到蓝图）
				- Consume ，会吃掉消息
					- 但是我们可能会存在“根据处理的情况决定吃不吃这个消息”的需要。
				- IC具有 BlockInput
			- 先收集一大堆信息，最后再根据情况和触发顺序一次性调用所有 Delegate
			- 然后PC的 PostProcessInput
				- 目前就是如果发现 Rotation 有但是功能不开启的话强制赋0
			- 最后 Finish 清空临时数据

## Updates in 4.20

### TODO


