# Nativization of Blueprint's input event

## Nativization result

**蓝图InputNode节点的C++化结果。**

构造函数里，最一开始会调用生成的 __CustomDynamicClassInitialization 方法：

```c++
ANewBlueprint_C__pf1010915279::ANewBlueprint_C__pf1010915279(const FObjectInitializer& ObjectInitializer) : Super(ObjectInitializer)
{

    /// *为了防止子类误调用和Default类误调用，这里做了防御*
    /// *Guard for derived class's constructor and DefaultObject(data only).*

    if(HasAnyFlags(RF_ClassDefaultObject) && (ANewBlueprint_C__pf1010915279::StaticClass() == GetClass()))
    {
        ANewBlueprint_C__pf1010915279::__CustomDynamicClassInitialization(CastChecked<UDynamicClass>(GetClass()));
    }

    // ...
}

```

这个方法在存在Input类的节点的时候，大概是像这样：

``` C++
void ANewBlueprint_C__pf1010915279::__CustomDynamicClassInitialization(UDynamicClass* InDynamicClass)
{
    // ...

    // *创建一个 DynamicBindingObject 并且注册到 Class 中。*
    // *Create a DynamicBindingObject and register it to the class.*
    auto __Local__0 = NewObject<UInputKeyDelegateBinding>(InDynamicClass, UInputKeyDelegateBinding::StaticClass(), TEXT("InputKeyDelegateBinding_1"));
    InDynamicClass->DynamicBindingObjects.Add(__Local__0);
    __Local__0->InputKeyDelegateBindings = TArray<FBlueprintInputKeyDelegateBinding> ();
    __Local__0->InputKeyDelegateBindings.AddUninitialized(1);
    FBlueprintInputKeyDelegateBinding::StaticStruct()->InitializeStruct(__Local__0->InputKeyDelegateBindings.GetData(), 1);
    auto& __Local__1 = __Local__0->InputKeyDelegateBindings[0];
    __Local__1.InputChord.Key = FKey(TEXT("LeftMouseButton"));
    __Local__1.FunctionNameToBind = FName(TEXT("InpActEvt_LeftMouseButton_K2Node_InputKeyEvent_1"));

}
```

由此可见，**最终仍然相当于是 DynamicBindingObjects 机制在起作用。**

# Process of input node's nativization
**蓝图Input节点的C++化过程**

### TODO

# Keywords

Nativization

Input

UnrealEngine

Blueprint

DynamicBindingObjects

