// Minimal Qt Widgets sample app for the k3rdp stack.
//
// It renders into the shared X11 display (provided via the DISPLAY env var,
// pointing at the x11rdp pod over TCP). The live clock + a click counter make
// it obvious the app is rendering and interactive when viewed over RDP.
//
// Swap this out for your own Qt application; the deployment only requires that
// the binary honors DISPLAY / QT_QPA_PLATFORM=xcb.

#include <QApplication>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QWidget>
#include <QTimer>
#include <QTime>
#include <QFont>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);

    QWidget window;
    window.setWindowTitle("k3rdp — Qt over X11/RDP");
    window.resize(1024, 1024);

    auto *layout = new QVBoxLayout(&window);
    layout->setContentsMargins(48, 48, 48, 48);
    layout->setSpacing(24);

    auto *title = new QLabel("Hello from Qt over X11/RDP");
    QFont titleFont = title->font();
    titleFont.setPointSize(24);
    titleFont.setBold(true);
    title->setFont(titleFont);
    title->setAlignment(Qt::AlignCenter);

    auto *clock = new QLabel;
    QFont clockFont = clock->font();
    clockFont.setPointSize(40);
    clock->setFont(clockFont);
    clock->setAlignment(Qt::AlignCenter);

    auto *counter = new QLabel("Clicks: 0");
    counter->setAlignment(Qt::AlignCenter);

    auto *button = new QPushButton("Click me");

    layout->addStretch();
    layout->addWidget(title);
    layout->addWidget(clock);
    layout->addWidget(counter);
    layout->addWidget(button);
    layout->addStretch();

    // Live clock — proves the event loop and rendering are alive.
    auto *timer = new QTimer(&window);
    QObject::connect(timer, &QTimer::timeout, clock, [clock]() {
        clock->setText(QTime::currentTime().toString("HH:mm:ss"));
    });
    timer->start(1000);
    clock->setText(QTime::currentTime().toString("HH:mm:ss"));

    // Interactivity — proves input events arrive from the RDP client.
    int clicks = 0;
    QObject::connect(button, &QPushButton::clicked, counter, [counter, clicks]() mutable {
        counter->setText(QString("Clicks: %1").arg(++clicks));
    });

    // Kiosk display: a single borderless, fullscreen window. This sets
    // _NET_WM_STATE_FULLSCREEN, which IceWM honors by dropping all decorations
    // and covering the whole 1024x1024 screen.
    window.showFullScreen();
    return app.exec();
}
