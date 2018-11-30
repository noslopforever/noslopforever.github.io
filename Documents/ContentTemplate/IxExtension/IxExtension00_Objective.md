# Abstract

想实现 ContentTemplate ，输入也是很重要的部分。

在 WPF 树中，各个级别的控件均可以设计自己的 Click 等事件，并为其挂接 Command 。整个 WPF 树执行的时候，先是 Tunnel 隧穿来确定谁会接受处理，然后 Buddle 冒泡来真实处理消息。

游戏对象一般不需要像 UI 那样复杂的树形体系，所以 UE 的输入系统在多数情况下是足够使用的。

但是类似 UI 那样的，不同叶子启用时，不同的输入需求是客观存在的，比如：

```
1.a 进入目标选择模式后，鼠标左键右键操作需要用来对游戏对象的选择。
1.b 进入区域选择模式后，鼠标左键需要映射为在地上拖拽一个区域。
2 正常模式下，左键右键用于当前控制对象的开火。
```

在标准的UE流程里，可以用很多种方法来做：

- 蓝图子对象：目标选择模式和区域选择模式做成两个专门的 Actor ，进入模式时， PlayerController 启用这两个 Actor 的 Input 。这样，自然而然地就完成了 Consume ，因此不会通知2的开火。
  - 这个方法的问题在于，这俩 Actor 到底算个啥东西？
  - 按理说，目标选择模式，应该算作 PlayerController 的某种输入状态机的概念范畴，这里相当于用 Actor 来作为状态机用了。
- 用代码相对更像回事，增加不同的 InputComponent 来处理不同的情况即可。

然而，想直接在蓝图里实现就麻烦了，蓝图的节点，要么就是完全 Consume ，要么就是不 Consume ，没有动态改变的可能性。

**无论如何，我们需要在输入对象中增加方法，根据条件来决定开启和关闭一些具体的输入通知，并且根据情况来做 Consume 。**


# Objective

考虑类似 WPF 的组织方式应该类似这样：

``` xml
<Root>
    <TargetSelectors Enable = "{Path = TargetSelectEnable}">

        <!-- 通过 TemplateSelector 来选择具体的 Template -->
        <TargetSelectors.TemplateSelector CheckValue="{Path = TargetSelectType}">

            <!-- 如果是 Object 就选择 ObjectSelector ，响应 LButtonClick -->
            <Object>
                <ObjectSelector 
                    LButtonClick = "CmdSelectObject" 
                    Enable="{Path = TargetSelectType}" 
                    >
                </ObjectSelector>
            </Object>

            <!-- 如果是 Area 就选择 AreaSelector ，响应 LButtonDown/Up -->
            <Area>
                <AreaSelector 
                    LButtonDown = "AreaSelectBegin"
                    LButtonUp = "AreaSelectEnd"
                    Enable="{Path = TargetSelectType}" 
                    >
                </AreaSelector>
            </Area>

        </TargetSelectors.TemplateSelector>

    </TargetSelectors>

    <!-- 标准 Pawn ，点击是开火 -->
    <PossessPawn 
        LButtonDown = "CmdFire"
        >

        <!-- Pawn 下方挂接的 Weapon ，Enable 的时候也应该直接截获输入。 -->
        <WeaponA 
            LButtonDown = "CmdWeaponAFire"
            >
        </WeaponA>

    </PossessPawn>

</Root>
````

根据树叶的情况来动态开启/关闭 InputBinding ，这个需求是应该有的。

另外还有一种常见的情况就是 Command 。

### TODO Command


