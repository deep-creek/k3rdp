// Multi-monitor Qt Widgets sample for the k3rdp stack.
//
// It renders into the shared X11 display (DISPLAY points at the x11rdp pod over
// TCP). The single X server presents two RandR monitors (primary 1024x1024 @ 96
// DPI, secondary 600x400 @ 120 DPI); this app opens one fullscreen window on
// EACH monitor, labeled with that monitor's geometry and DPI, so the setup is
// visually verifiable over RDP. A live clock proves the event loop is running.
//
// Swap this out for your own Qt application; the deployment only requires that
// the binary honors DISPLAY / QT_QPA_PLATFORM=xcb.

#include <QApplication>
#include <QScreen>
#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>
#include <QTimer>
#include <QTime>
#include <QFont>
#include <QString>
#include <QDebug>
#include <vector>
#include <cstdio>

// Build one panel widget describing a screen/region. `title` names the monitor,
// `info` carries the geometry + DPI lines.
static QWidget *makePanel(const QString &title, const QString &info)
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
    layout->addStretch();
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

    // One fullscreen window per detected monitor.
    for (int i = 0; i < screens.size(); ++i) {
        QScreen *s = screens[i];
        const QString title = (i == 0 ? QString("Primary monitor") : QString("Secondary monitor"));
        QWidget *w = makePanel(title, screenInfo(s));
        // Pin the window to this screen, then go fullscreen on it (Qt6).
        w->setScreen(s);
        w->setGeometry(s->geometry());
        w->showFullScreen();
        windows.push_back(w);
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
        QWidget *w = makePanel("Secondary region (fallback)",
                               QString("%1 x %2 at (%3, %4)\n(placed by absolute geometry)")
                                   .arg(sw).arg(sh).arg(sx).arg(sy));
        w->setWindowFlag(Qt::FramelessWindowHint, true);
        w->setGeometry(sx, sy, sw, sh);
        w->show();
        windows.push_back(w);
    }

    return app.exec();
}
