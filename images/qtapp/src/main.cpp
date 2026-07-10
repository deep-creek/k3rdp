// Multi-monitor Qt Widgets sample for the k3rdp stack.
//
// It renders into the shared X11 display (DISPLAY points at the x11rdp pod over
// TCP). The single X server presents two RandR monitors (primary 1024x1024 @ 96
// DPI, secondary 600x400 @ 120 DPI); this app opens one fullscreen window on
// EACH monitor, labeled with that monitor's geometry and DPI, so the setup is
// visually verifiable over RDP. A live clock proves the event loop is running,
// and a continuously-updating readout shows the current mouse position.
//
// Swap this out for your own Qt application; the deployment only requires that
// the binary honors DISPLAY / QT_QPA_PLATFORM=xcb.

#include <QApplication>
#include <QScreen>
#include <QCursor>
#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>
#include <QTimer>
#include <QTime>
#include <QFont>
#include <QString>
#include <QPoint>
#include <QDebug>
#include <vector>
#include <cstdio>

// Build one panel widget describing a screen/region. `title` names the monitor,
// `info` carries the geometry + DPI lines. The panel's mouse-position label is
// returned via `mouseLabelOut` so the caller can update it from a shared timer.
static QWidget *makePanel(const QString &title, const QString &info, QLabel **mouseLabelOut)
{
    auto *w = new QWidget;
    w->setWindowTitle("k3rdp — " + title);

    auto *layout = new QVBoxLayout(w);
    layout->setContentsMargins(32, 32, 32, 32);
    layout->setSpacing(16);

    auto *heading = new QLabel(title);
    QFont hf = heading->font();
    hf.setPointSize(20);
    hf.setBold(true);
    heading->setFont(hf);
    heading->setAlignment(Qt::AlignCenter);

    auto *detail = new QLabel(info);
    detail->setAlignment(Qt::AlignCenter);
    detail->setTextInteractionFlags(Qt::TextSelectableByMouse);

    auto *clock = new QLabel;
    QFont cf = clock->font();
    cf.setPointSize(28);
    clock->setFont(cf);
    clock->setAlignment(Qt::AlignCenter);

    auto *mouse = new QLabel("Mouse: —");
    QFont mf = mouse->font();
    mf.setPointSize(14);
    mouse->setFont(mf);
    mouse->setAlignment(Qt::AlignCenter);

    auto *timer = new QTimer(w);
    QObject::connect(timer, &QTimer::timeout, clock, [clock]() {
        clock->setText(QTime::currentTime().toString("HH:mm:ss"));
    });
    timer->start(1000);
    clock->setText(QTime::currentTime().toString("HH:mm:ss"));

    layout->addStretch();
    layout->addWidget(heading);
    layout->addWidget(detail);
    layout->addWidget(clock);
    layout->addWidget(mouse);
    layout->addStretch();

    if (mouseLabelOut)
        *mouseLabelOut = mouse;
    return w;
}

static QString screenInfo(const QScreen *s)
{
    const QRect g = s->geometry();
    return QString("name: %1\n%2 x %3  at  (%4, %5)\nlogical DPI: %6\nphysical DPI: %7")
        .arg(s->name())
        .arg(g.width()).arg(g.height())
        .arg(g.x()).arg(g.y())
        .arg(qRound(s->logicalDotsPerInch()))
        .arg(qRound(s->physicalDotsPerInch()));
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);

    const QList<QScreen *> screens = QGuiApplication::screens();
    qInfo() << "[qtapp] detected" << screens.size() << "screen(s)";
    for (const QScreen *s : screens)
        qInfo().noquote() << "[qtapp] screen:" << s->name()
                          << s->geometry() << "phys-dpi" << s->physicalDotsPerInch();

    std::vector<QWidget *> windows;
    std::vector<QLabel *> mouseLabels;

    // One fullscreen window per detected monitor.
    for (int i = 0; i < screens.size(); ++i) {
        QScreen *s = screens[i];
        const QString title = (i == 0 ? QString("Primary monitor") : QString("Secondary monitor"));
        QLabel *mouseLabel = nullptr;
        QWidget *w = makePanel(title, screenInfo(s), &mouseLabel);
        // Pin the window to this screen, then go fullscreen on it (Qt6).
        w->setScreen(s);
        w->setGeometry(s->geometry());
        w->showFullScreen();
        windows.push_back(w);
        if (mouseLabel)
            mouseLabels.push_back(mouseLabel);
    }

    // Fallback: if Qt only exposed one screen (e.g. it ignored the no-output
    // RandR virtual monitor), still demonstrate the secondary region by placing
    // a borderless window at its absolute framebuffer geometry.
    if (screens.size() < 2) {
        qWarning() << "[qtapp] only one QScreen seen — using geometry fallback for the secondary region";
        const QByteArray geo = qgetenv("SECONDARY_ABS_GEOMETRY"); // "WxH+X+Y", optional override
        int sw = 600, sh = 400, sx = 0, sy = 624;
        if (!geo.isEmpty())
            std::sscanf(geo.constData(), "%dx%d+%d+%d", &sw, &sh, &sx, &sy);
        QLabel *mouseLabel = nullptr;
        QWidget *w = makePanel("Secondary region (fallback)",
                               QString("%1 x %2 at (%3, %4)\n(placed by absolute geometry)")
                                   .arg(sw).arg(sh).arg(sx).arg(sy), &mouseLabel);
        w->setWindowFlag(Qt::FramelessWindowHint, true);
        w->setGeometry(sx, sy, sw, sh);
        w->show();
        windows.push_back(w);
        if (mouseLabel)
            mouseLabels.push_back(mouseLabel);
    }

    // Continuously show the mouse position. Polling QCursor::pos() tracks the X
    // pointer everywhere (no focus / mouse-tracking needed) and works across both
    // monitors; every panel's readout is refreshed from this one timer.
    auto *mouseTimer = new QTimer(&app);
    QObject::connect(mouseTimer, &QTimer::timeout, &app, [mouseLabels]() {
        const QPoint p = QCursor::pos();
        QScreen *s = QGuiApplication::screenAt(p);
        QString text;
        if (s) {
            const QPoint local = p - s->geometry().topLeft();
            text = QString("Mouse: global (%1, %2)\non %3: local (%4, %5)")
                       .arg(p.x()).arg(p.y())
                       .arg(s->name()).arg(local.x()).arg(local.y());
        } else {
            text = QString("Mouse: global (%1, %2)").arg(p.x()).arg(p.y());
        }
        for (QLabel *l : mouseLabels)
            l->setText(text);
    });
    mouseTimer->start(30);   // ~33 Hz — smooth, continuous updates

    return app.exec();
}
