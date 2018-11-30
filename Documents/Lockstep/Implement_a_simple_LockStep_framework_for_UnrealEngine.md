# 在UnrealEngine中实现简单的LockStep框架

转载本文请注明[出处](https://noslopforever.github.io/Documents/Lockstep/Implement_a_simple_LockStep_framework_for_UnrealEngine)，本文后续可能会继续修改。

本文对应的[代码工程](https://github.com/noslopforever/NFUESample_VehicleAdvLockStep)也在github上，后续也会随着文档更新。

# 引子
今年早些时候，跟朋友讨论的时候偶尔接触到了一个问题，“强物理游戏用帧同步（Lockstep）是否可行？”。当时闹了个大笑话，也是想都没想，一拍脑门、基于一个错误的印象、给出了一个否定的答案，但是后面跟其他朋友的讨论过程中当然迅速就发现问题，又赶紧修正之前的观点。

也感谢这次犯下的错误，使得自己终于下决心实现一次帧同步。

于是年中左右花了一点时间，在自己的习作里（本来设计为状态同步）下做了一些Lockstep方面的及其初级的尝试，达成了一些初步目标。

最近家里的琐事收拾差不多，心情放松了一些，断断续续地，在虚幻自带的例子里重新组织一下（习作有点太臃肿了，结构上也有不少胡搭乱建的迹象，乱七八糟的东西太多），也算是把思路沉淀一下。

当然，还是强调一下，个人的理解和方法不见得正确，仅供参考，欢迎批评指正。

# LockStep同步模式简介
帧同步本身并不是什么新东西，早期的局域网联机游戏里这是一种比较主流的实现方式。但是自己参与的项目一直没有使用这个的机会，而自己虽然有自己做这个的打算，但是也一直卡在自己那不成器的服务器实践上，后来随着各种事情忙来忙去，也就这样放着了。

它的原理是，程序只要确保在不同的终端上，所有方法的执行顺序、入参都一致，那么结果必然也是一致的。

一般游戏逻辑的执行顺序保持一致是很容易的，唯一会对其造成影响的，主要就是外界用户的输入，因此只要保证所有用户的输入在各个终端上的执行时机和顺序也是一致的就可以了。

换个角度来想，可以把LockStep想象成一个速度更快的回合制游戏，回合制游戏下，一个回合内，每个用户按照顺序执行输入，全部完成输入后，开始下一个回合。LockStep则是在一个Step时间片内，收集所有用户的输入，并且按照统一的顺序统一应用它们。

![LockStep的同步](https://noslopforever.github.io/Documents/Lockstep/images/Conception_LockStep.svg)

可以看出，LockStep机制最核心的就是，**保证逻辑、包括玩家输入部分的逻辑处理，在所有终端上的执行顺序和参数是完全一致的。**只有这样才能保证每个Step走完后，各终端的结果一致。

为了完成这个目的，**首先就是Step由服务器统一发布，各客户端逻辑只有收到Step通知后才做，而且每个终端执行Step时的DeltaTime一致。**

**其次，就是Input需要由服务器收集起来，随着Step一同发布，客户端按照统一的顺序来执行这些Input。**

在此之上，要保证这个流程完全一致，本身也有一些需要注意的：
- 需要注意**随机数发生器**，确保在任意机器上，同一条件下的随机数计算，结果一致。
- 需要注意**算术精度**问题，确保在输入数据一致的情况下，不同平台计算的结果一致。特别是，浮点数的计算误差会不断累积，甚至带入下一帧计算中去。
- Step消息要按照一个什么样策略发动？等待全部客户端执行完一帧后？还是就按照固定的时间？根据不同情况，可以设计出不同的策略。
- 网络通信是存在波动的，因此Step也是会有波动，这次是50 ms到了，但是下一次可能是70 ms才到，但是渲染则可能是16.67 ms一帧。如何消除这种波动？
- 跳帧，客户端卡了一下，连续收到了多个Step的通知。比如一个Step设定为50 ms，但是较慢的终端上一帧执行完就已经过去了150 ms，所以这一帧开始执行的时候，已经收到了3个Step，接下来需要追赶这个进度。

这些都是帧同步的经典问题，介绍帧同步的文章也都会写（[参考资料](#参考资料)）。细节我们这里暂时不展开讨论，根据项目的不同，解决的方案也不一定会完全一致，目前我们先聚焦于实现一个简单的同步框架。

# 目标

考虑一下我们希望用LockStep实现一个什么目标。我们考虑基于虚幻自身的Examples来修改，因为这样方便于在传统模式和LockStep模式间进行比较，更方便理解。

最终，在所有的Examples中，我们选择**VehicleAdvanced**来作为基础模板，将其修改为LockStep。

这个主要基于这个模板各方面的东西都有一些，比较方便更全景一些地展示LockStep。另外就是这个模板比较多使用了物理，就目前而言，在服务器进行全面的物理计算是压力比较大的，笔者认为LockStep用在这类游戏里会比较有利。

# 改造计划
## 虚幻现有相关框架简介

在开始工作前，我们需要先对虚幻自己的系统做一些回顾，以确定我们的修改大概会牵扯到哪些部分的修改和扩展。

### - 服务器形态、Role和RPC/Replicate

请参考这篇文章：

[UnrealEngine4 Net System Overview](../UEStudy/NetworkBasic/UENet_Overview.md)

针对 LockStep ，这里有一些需要注意的事情：

**LockStep 机制下，近乎所有的物体都是在客户端创建的，全是客户端具备 Authority 、服务器不存在的。**所以说， RPC 机制由于更看重 NetMode ，所以这里兴许会有点问题。

另外就是 Replicate 机制， Replicate 想要起作用，就必须得是在服务器端拥有 Authority 的实体，然后才能自动刷新到客户端。不过，可惜的是，如前所述，**LockStep机制下，服务器基本没有真实存在的实体，所以这个机制是基本处于冷板凳状态的。**

当然我们自己写的方法，注意到这些事情，一般不会出问题，但是虚幻本身的一些 RPC 和 Replicate 机制则就有可能会引发问题，无法达成预期效果。这种情况下就需要做出一些修改。

### - 游戏框架
游戏框架就是GameMode/GameState/PlayerState/PlayerController/Pawn这一系列东西。

- GameMode一般用来确定游戏世界的核心状态机，比如，前一分钟内是游戏准备时间，到时间后再传送玩家并开始游戏计分，计分到达某个程度，游戏结束并通知全体玩家。GameMode同时管理玩家登录和退出游戏时的一些细节行为，比如可以让玩家在开局3分钟后就不能再进入游戏，之类的。联机模式下，GameMode在客户端不存在，仅在服务器端存在。

- GameState是会同步到所有客户端的，适合用来管理游戏本身的一些公开的状态信息，比如当前游戏的组队分配、游戏Progress、倒计时等等。

- 玩家通过在GameMode中Login来产生新的PlayerController，虽然叫Controller让人总觉得就是个控制器，事实上这个多数时刻可被理解为某个玩家了（尽管UPlayer看起来更对应玩家的概念）。
  - PlayerController在服务器存在，同时，哪个客户端登录服务器时创建了这个PlayerController，就在哪个客户端存在，在其它客户端不存在。
  - 也就是，不同玩家的PlayerController一般互相是不会同步的，玩家在自己的电脑上，只能获取到属于自己这个客户端的PlayerController。

- PlayerState跟GameState一样，会同步到所有客户端，如果客户端之间有公开的需要同步的信息，走这个就对了。比如玩家积分、姓名、从属的队伍，等等。

在联机模式下，这几个类大致的情况，在Dedicated Server模式下：

![DS模式下的游戏框架](https://noslopforever.github.io/Documents/Lockstep/images/GameFramework_DS_C.svg)

在Listen Server模式下：

![LS模式下的游戏框架](https://noslopforever.github.io/Documents/Lockstep/images/GameFramework_LS_C.svg)



## 修改计划
一个简单的LockStep同步至少需要实现下面的功能：
- 客户端：
  - 收集本地操作，告知服务器
  - 处理服务器派发过来的同步帧
- 服务器：
  - 主要是侦听玩家发出的操作消息
  - 确定同步帧的时机并告知各客户端

绘图如下：

![基本的结构图](https://noslopforever.github.io/Documents/Lockstep/images/Design_SequenceDesign.svg)

这里面我们首先需要注意，对于典型的LockStep而言，除了整个游戏框架那些根本绕不开的概念，也就是GameMode、GameState、PlayerController、PlayerState、World（umap、关卡蓝图）之外，**服务器本身一般是不同步其它游戏对象的信息**，即便是那些已经安置在关卡中的对象也是如此，它们应当被设置为不进行Replicate。

客户端操作一般由PlayerController入口，输入消息通过PlayerController的InputStack来调度给Pawn和其他EnableInput的对象。

- 这里，由于在LockStep机制下，Pawn和其他EnableInput的Actor都是纯客户端的，在服务器没有对等实体，因此就只剩下PlayerController来同步操作信息给服务器的好地方。
- 客户端的PlayerController通过RPC告知自己在服务器端的对应实体，由于服务器知晓全部的PlayerController，也自然可以获知这些操作信息了。
- 具体开发时，派生并为其添加一些C2S方法，或者为其挂一个Component来做C2S通知，都可以达成目标，根据实际情况选择即可。

客户端操作发上来后，在服务器确定同步帧时机。

首先，我们可以确认，这个时机的控制，基本上都是在服务器端确定的，客户端没有必要参与（当然兴许会需要一些从客户端收集上来的信息）。所以这个**确认Step时机的处理模块，应该是跟GameMode绑在一起的**，因为GameMode是只在服务器端存在，在客户端不存在。当然也可以自己在服务器创建一个Actor，关闭其Replicate，也能达到同样的效果，但是感觉上可能就多此一举了。GameMode先天就具有这样的性质，利用起来即可。

然后，同步时有很多具体策略。

- 最简单的就是不管三七二十一，每50 ms通知一次。但这样的话，客户端可能各自帧就会不一样了，延迟大的总会慢人一拍，很有挫败感。
- 最严谨的，就是每一次服务器步进，除了考虑到时间间隔外，还要考虑从客户端是否收到上一帧的回应。如果没有，整个服务器就不步进了，相当于回到了回合制。但是这样的话，速度快的电脑总要去等待速度慢的电脑，无法获得自己本应获得的游戏体验。

简直是个典型的“平等与正义”问题。[如何评价这幅关于平等与正义的漫画？](https://www.zhihu.com/question/23404243)   [What are some points in favour of reservation?](https://www.quora.com/What-are-some-points-in-favour-of-reservation)

![平等？正义？](https://pic1.zhimg.com/e745bbeb024db9194e4e63dc80919604_b.jpg)

当然在这里我们不准备讨论哲学问题。

就简单而言，我们倾向于先**实现一套不管三七二十一、每间隔一定时间通知一次的通知机制**。毕竟如果这个地方想做得复杂的话，可以做隔上几十上百Step再确认各方是否同步的机制，可以做投票踢人机制，甚至有那种根据客户端连接情况和速率不同，动态调整Step间隔和游戏节奏的实现，这还是看项目的需求来做的好。


# 实施记录
## 确定基本接口和数据结构
根据粗略设计《[修改计划!](#修改计划)》，首先我们先确定最基本的模块、接口和数据结构。

如前所述，修改可以是继承，也可以是挂Component，个人习惯上，考虑是加挂Component的机制。

这样我们就需要：
- **实现一个挂接在GameMode的ServerLockStepComponent，用于确定Step时机并发布StepAdvance消息。**
- **实现一个挂接在PlayerController的ClientLockStepComponent，用于接收StepAdvance消息，并做处理。**
- 简单起见，我们考虑玩家控制消息都发String即可

服务器发StepAdvance时，一个Step内可能收到很多个客户端的不同的控制消息，所以数据结构应该像这样：

![服务器到客户端通知的数据结构](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_StepActionInfo.png)

这样，我们需要确保我们LockStepDemo使用一个我们自定义的GameMode，这个GameMode需要挂接一个ServerLockStepComponent。


## 实现最简单的Step通知
第一步我们首先试图实现一套最简单的Step通知，也就是，服务器确定Step时机，发布给客户端。

按照计划，首先我们提供两个Component：**ServerLockStepComponent**和**ClientLockStepComponent**，从ActorComponent派生即可。

LockStep游戏开始时，需要做一些准备，在ServerLockStepComponent里增加一个AuthStartLockStepGame方法，添加如下代码：

![ServerLockStepComponent::AuthStartLockStepGame](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ServerLockStepComponent__AuthStartLockStepGame.png)

在这里面我们为所有PlayerController挂接必要的ClientLockStepComponent，这样开发PlayerController的时候，不需要再手动为其添加这个Component了，防止忘了操作导致的不必要的麻烦。

当然这里也可以做很多别的事情，比如通知客户端LockStep游戏开启了，简单起见我们就不再继续了。

下面是确定**Step的时机**，如前所述，我们考虑最简单粗暴的，按照时间来确定Step。

在服务器ServerLockStepComponent的TickComponent中添加如下代码：

![ServerLockStepComponent::TickComponent](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ServerLockStepComponent__TickComponent.png)

服务器累积一个时间，只要超过了我们设定的某个周期，就触发一次StepAdvance通知。

通知的时候，通过每个PlayerController挂接的ClientLockStepComponent来发送Server到客户端的RPC消息：

![ServerLockStepComponent::AuthDoStepAdvance](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ServerLockStepComponent__AuthDoStepAdvance.png)

为ClientLockStepComponent添加S2C_StepAdvance的RPC方法，在这个方法里下断点，就可以检验是否成功发出StepAdvance消息了。

这里，如果要测试的话，需要派生一个GameMode蓝图，为其挂接ServerLockStepComponent，并在蓝图的合适时机调用AuthStartLockStepGame。

![GameMode的组件和蓝图](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_MyGameMode.png)

我们这里取的是游戏服务开启两秒后。

## 客户端更新

我们可以选择在客户端收到S2C_StepAdvance时，直接进行Step的更新操作，但是个人更倾向于先把Step都获取下来，后续在Tick时再统一处理。因为Step是一个个发过来的，但是客户端卡的情况下，可能实际上本帧会收到多个Step包，如果全部收集下来，后续我们就可以根据情况做一些追赶或者卡帧的处理。

此外，此时其实World的各个TickGroup普遍都还没有开展工作，在后续把Physics整合到Step体系时，由于Physics的更新是有某个TickGroup的前置条件的，这样就无法正常WaitPhysics并且Fetch计算结果了（本线程Wait本线程后续信号，直接卡死）。在后续介绍Physics整合的场合，我们会详细展开这个点。

因此这里，我们S2C_StepAdvance实际上就是把Step信息缓存到客户端的某个池子里，留待Tick时处理。

Tick这里有个小问题需要考虑，虚幻自身有一套WorldTick了，这里最直接的考虑是改引擎代码：*Step消息过来时，通过修改最外层Tick的DeltaTime为Step时间，来得到我们期望的结果。这样做的好处是蓝图的接口不需要任何调整，AI蓝图、EventTick之类的都还可以正常使用。*

但其实，这条路没有想象中那么好。Step每隔50 ms才过来一次，这个过程中WorldTick不可能在那干等。**Step过来时的处理和Step没来时的处理是有区分的，这就需要增加某种“当前这一帧是Step帧”这样的东西。**这样事实上最终逻辑维护起来并不会简单多少，同样要付出区分Step和Frame的心力。

**从根本上说，Step帧和Frame帧确实是需要被区分的。LockStep下，Step帧负责逻辑更新，Frame帧负责表现更新，这个工作量是偷不了懒的。**

所以就只有另一种方案了，就是尽可能不动引擎的核心Tick，而是争取通过代理、继承来解决问题。

按照这个思路，我们在ClientLockStepComponent::BeginPlay里面挂接我们自己的Tick代理，并且实现这个代理：

![客户端Tick代理](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ClientLockStepComponent__OnWorldPostActorTick.png)

其功能目前就是把之前入队的Steps执行起来。

执行代码中，最主要的就是两个部分，执行所有ClientAction，以及通知所有需要被通知的Actor，Step来了：

![客户端Step执行](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ClientLockStepComponent__ProcessQueuedSteps.png)

## 客户端初始化时机、对象创建、控制

正常情况下，虚幻的游戏初始化，游戏对象要么是一开始布置在关卡中，要么是通过Level蓝图在BeginPlay时来创建，要么就是GameMode在合适的时机触发创建。

**但是在LockStep的情况下，布置在关卡中的游戏对象，必须取消Replicate。通过Level蓝图BeginPlay创建也好，通过GameMode触发创建也罢，都不能再直接这么用了，因为这些都是在服务器端触发的，违反了我们LockStep游戏对象必须在客户端创建的假设。**

这个过程理应由专门的“游戏开始”这类的消息来触发。我们这里图省事儿，**在Level蓝图收到Step消息首帧（StepIndex为0）时，来在客户端执行真正的创建**。

这里我们简单起见，根据调用时玩家池的数量（PlayerArray）的大小来创建不同数量的Pawn，这里需要注意，不能直接使用GameState的PlayerArray，因为这个Array在不同客户端的顺序不同，而**LockStep下，确保顺序一致是很重要的**。

还有一点需要注意，Host模式下，Host主机同时起服务器的作用，所以在Host主机上创建的Pawn，**需要关闭Replicate**，否则会自动被同步到其他客户端。LockStep机制下，各个客户端互相之间不应该同步任何游戏对象。

**由于在客户端创建，所以我们创建出来的Pawn，在服务器端是没有对等实体的。**未来同步操作消息的时候，我们需要同步操作的是哪个对象，此时由于Pawn在服务器端没有实体，因此试图像默认RPC机制那样同步指针就不现实了。所以这里我们必须**建立一个Pawn表，为创建出来的这些Pawn来分配编号，顺带也就需要提供我们自己的Spawn节点**。所有这些处理，都放到了ClientLockStepComponent里面：

![CreatePawn和FindPawn](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_CreateAndFindPawn.png)

默认情况下，虚幻的PlayerController必须是Possess在服务器端存在实体的Pawn，但是在目前的情况下就不现实了。

所以这里我们需要**派生一个专门的PlayerController，为其增加针对性的LockStepPossess**：

![LockStepPossess](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_LockStepPC__LockStepPossess.png)

相当于是把服务器版的Possess简化抽取出来，当然这样的做法充满了坏味道，后续应该还会有许多问题。但是基本上这里要想让Pawn接收到输入，不损害虚幻本身的默认假设是很困难的。**可能只能确保说后续的逻辑开发，都处于某种受控的条件下，提供一系列项目特定的节点和方法，屏蔽掉引擎本身的一些节点和方法，并且核心接口由LockStep系统的设计者参与设计。**

整个创建过程，请参考Demo工程的关卡蓝图：

![LockStep游戏开始时的创建工作](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_CreateVehicleWhenLockStepStart.png)

到这一步为止，如果在编辑器内开启多人测试的话，应该能看到跟全部客户端数量相同的车，在各自的客户端上创建出来，且不同客户端Focus的车是不一样的。

## 同步Actions
接下来，考虑同步玩家操作。

首先是在Pawn的输入处理里面，把直接的操作改为发送消息。客户端我们可以获取到属于这个客户端的LocalPlayerController，这样也就可以获得其身上挂接的ClientLockStepComponent，然后通过ClientLockStepComponent的C2S_RequestStep发送消息给服务器即可：

![输入消息处理](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ClientActionRequest.png)

这里C2S_RequestStep是一个RPC方法，运行在Server端，消息中需要带上我们当前操作的是哪辆车的ID，如前所述，不带ID的话，同步给其他玩家，其他玩家是没办法定位到“操作的到底是谁”的。

服务器收到消息后，将其插入到ServerLockStepComponent的ServerCurrentStepInfo中。这样下一帧AuthDoStepAdvance的时候，随着ServerCurrentStepInfo就会一同被发给全部客户端。

![服务器Gather输入消息](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ServerGatherActionRequest.png)

日志或者断点，如果没有异常情况的话，消息会很正常地发到服务器，并最终同步给所有其他客户端。

## 物理纳入LockStep

到目前为止，车应该是能开了。但是实际上，如前所述，物理本身目前还没有纳入LockStep。

在编辑器模式下跑的话，应该同步的问题并不是特别大，因为每个模拟客户端得到的时间片基本是一致的，但是在实际的游戏中，不同客户端的Tick时间片是不可能一致的。

而PhysX的计算，对于时间是很敏感的。**对于PhysX而言，如果两个场景的初始状态完全一致，simulate处传入的时间一致，那么最终的结果也必然完全一致。**

**但是，如果时间不一致，哪怕是一个客户端算了50 ms，另一个客户端是2*25 ms，最终的结果也会有很大的可能不一致。**

VehicleAdvanced是通过物理来完成位移处理的，而位移处理可以说是游戏系统最重要的处理项之一，所以，我们这里也需要把物理纳入到LockStep体系的管理下。

简单来说，我们需要做的是下面几件事情：
1. 首先，关闭World自身的PhysicsTick，这个可以通过设置**UWorld::bShouldSimulatePhysics**成员为false来实现。
1. 第二，在我们自己的[客户端StepTick更新](#客户端更新)里面，在合适的时机来做Physics的Update。

所以我们首先在ClientLockStepComponent::BeginPlay里面关闭掉bShouldSimulatePhysics，当然这个具体的触发时机，可以根据需要做调整。总之，**在游戏世界的任何物理体开始更新前，就需要做好这件事。**

而具体的物理更新代码如下：

![客户端物理更新](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ClientStep_UpdatePhysics.png)

到此为止，基本上主要的框架就构建起来了，接下来开始编译、调试。

## 突发！移动组件的特殊处理
如果一路做到这里，那么首次调试应该会遇到问题，玩家的操作不会实际执行，这是为什么呢？

跟踪以后发现，虚幻默认的4轮车UWheeledVehicleMovementComponent4W本身就是基于传统的服务器-客户端结构进行设计，所以，当我们的输入消息发给了UWheeledVehicleMovementComponent4W之后，在它UpdateState的时候，试图把消息通过RPC发给服务器（%UE_ROOT%/Engine/Plugins/Runtime/PhysXVehicles/Source/PhysXVehicles/Private/WheeledVehicleMovementComponent.cpp）：

![ServerUpdateState](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_CallServerUpdateState.png)

这个ServerUpdateState是一个RPC的Server Function。

RPC这个机制在默认情况下，即便创建的是纯客户端对象，机制本身也会试图把消息发给Server，然而此时是根本找不到对应的Server对象的。（对这个机制感兴趣，请移步AActor::GetFunctionCallspace）

所以我们需要从默认的UWheeledVehicleMovementComponent4W派生一个我们自己的ULockStepWheeledVehicleMoveComp4W，然后重新实现这个方法，将其改为纯客户端的版本。

![Movement的改动](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_ULockStepWheeledVehicleMoveComp4W__UpdateState.png)

并且，Pawn那里创建Movement的地方也要做少许修改：

![Pawn替换Movement](https://noslopforever.github.io/Documents/Lockstep/images/CodeLog_Pawn_ChangeDefaultMovement.png)

至此为止，基本上就跟我们github上的代码差不太远了，编译，运行，应该是可以直接通过了：

![Result!](https://noslopforever.github.io/Documents/Lockstep/images/DemoScreenGif.gif)

## 后续计划

这里其实后续还有问题需要处理

1. 比如，**即便传入的时间一致，但是PhysX在不同硬件环境下，浮点运算的结果仍然可能不一致**，这就需要**把数据取回来，做一下钳制，丢弃掉部分精度，以防止积累误差。**这个我们在之前工程的实验中已经确定是可以走通的了，具体方法就是，**在我们自己物理处理的EndFrame之后，找到所有物理体，获取位置、旋转、速度、角速度，做钳制，然后再硬设置回去即可。**

1. 还有就是，目前的画面给人的感觉卡卡的，这是因为缺乏了某种视觉上的平滑机制，LockStep一切片在我们的工程里面最少也要50 ms，自然是不可能像60fps那般丝滑。这就需要某种“逻辑位置”和“视觉位置”之间的同步机制。粗略考虑起来，MovementComponent本身有一个SetUpdateComponent的机制，可以利用这个来储存逻辑位置，然后视觉上的SkeletalMesh跟这个逻辑位置之间做插值。

1. 另外，目前物理这里这么做之后，车速提不起来了，按理说不应该的。跟我们年中时做的习作表现也不是很一致，当时用的虽然不是VehicleMovement，但是自己Movement也是纯物理驱动的，速度就不怎么受影响，这个问题后续也得继续查一查。

1. 还有就是，从大厅到游戏的整个过程。只有实现了这个，才能正常发布服务器/客户端。

后续我们还会继续维护这个工程和这个文档，包括各种补充文档。

# 结论和展望

尽管花了一些功夫，实现了一个简单的LockStep同步框架，但是，如本文描述的那样，还是有不少问题的。

个人认为，所有问题中最大的问题是，帧同步框架与虚幻许多内置系统假设之间的冲突，这一点相信大家也能看得出来，各种绕虚幻自身假设。尽管就具体的项目而言，总会有方法可以绕过这些冲突和限制，但是，这种冲突就意味着我们的LockStep同步框架很难做出某种符合虚幻引擎“一般套路”、或者具备一定“一般性”的方案，每个项目的开发者需要自己去定夺，提出项目特定的工作流。

> 比如我们的实践里，把游戏Pawn的创建和控制放在LevelScriptActor里面，而不是虚幻框架更推荐的GameMode里。
>
> 还有就是逻辑性的处理都必须放到Step通知里去做了，而不是Event Tick。至少在做这些具体逻辑的时候，是需要小心一些的。

本文虽然介绍LockStep，却并不代表认为这是一个非常完美的方案和方向。

根据之前的描述，LockStep具有下面的特点：
- 首先是需要确保逻辑流程在各个客户端的顺序和参数完全一致。
- 在此基础上，仅同步操作，通信频率仅取决于网络状况。因此更适合对操作频率要求较高的游戏。
- 服务器无逻辑运算，几乎不需要进行特殊的同步处理。客户端建主也很方便，没有需要任何特殊处理的地方。因而服务器也没有运算压力，压力全在通信上，在哪怕最低档次的云服务器上（当然网速和流量得有保证）也能表现良好。
- 客户端底层平等具备全部信息，包括对手的信息。这并不是个优点，反开图挂会是一个大问题，但是相应来说，Replay和直播会很方便做。
- 主要的逻辑基本都可以等同纯单机来处理，所以把该封的口封好，做起逻辑本身还是相对简单的。

所以，基于这些特点，比如做那种服务器运算压力大、同步信息量巨大、同步频率高的项目，不妨就可以考虑评估一下LockStep机制。

事实上，随着5G时代的逼近，LockStep在未来是否真的还有很大的必要性，本身可能也有一定疑问。总之，既然采取了LockStep方案，就还是得明白它本身带来的优势和所有麻烦的地方。

最后，如果您有更好的建议，请一定要不吝赐教，欢迎各种发信或者留言吐槽。

祝愿大家都好运！

# 附录

## 关于AI
施工中……

# 参考资料

- [Lockstep Implementation in Unity3D](http://clintonbrennan.com/2013/12/lockstep-implementation-in-unity3d/)  译文：[Unity3D中实现帧同步 - Part 1](http://jjyy.guru/unity3d-lock-step-part-1)

- [Lockstep Implementation in Unity3D part 2](http://clintonbrennan.com/2014/04/lockstep-implementation-in-unity3d-part-2/)  译文：[Unity3D中实现帧同步 - Part 2](http://jjyy.guru/unity3d-lock-step-part-2)

- [游戏中的网络同步机制——Lockstep](https://bindog.github.io/blog/2015/03/10/synchronization-in-multiplayer-networked-game-lockstep/)

- [lockstep 网络游戏同步方案](https://blog.codingnow.com/2018/08/lockstep.html)

- [帧同步（LockStep）该如何反外挂](http://gad.qq.com/article/detail/41402)
