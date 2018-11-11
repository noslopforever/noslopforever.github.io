for /r "./" %%i in (*.dot) do  (
    dot %%i -T svg -o %%~dpni.svg
)