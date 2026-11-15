using System.Threading;
using System.Windows;

namespace MAFloater.App;

public partial class App : System.Windows.Application
{
    private Mutex? singleInstance;

    private void Application_Startup(object sender, StartupEventArgs e)
    {
        singleInstance = new Mutex(true, @"Local\MAFloater.Native", out var createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        MainWindow = new MainWindow();
        MainWindow.Show();
    }

    private void Application_Exit(object sender, ExitEventArgs e)
    {
        if (singleInstance is null)
        {
            return;
        }

        try
        {
            singleInstance.ReleaseMutex();
        }
        catch (ApplicationException)
        {
        }

        singleInstance.Dispose();
    }
}
