Name:       harbour-readeck

Summary:    Read-it-later client for Readeck
Version:    1.0.0
Release:    1
License:    MIT
URL:        https://github.com/example/harbour-readeck
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   sailfish-components-webview-qt5
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  desktop-file-utils
BuildRequires:  cmake

%description
Readeck is a self-hosted read-it-later / bookmark application. This is a
native Sailfish OS client: browse your unread, archived and favorite
bookmarks, read articles offline-friendly in a clean reader view, save new
links, and manage labels and favorites.

%if 0%{?_chum}
Title: Readeck
Type: desktop-application
DeveloperName: Readeck for Sailfish contributors
Categories:
 - Network
 - Office
Custom:
  Repo: https://github.com/example/harbour-readeck
Links:
  Homepage: https://github.com/example/harbour-readeck
  Bugtracker: https://github.com/example/harbour-readeck/issues
%endif


%prep
%setup -q -n %{name}-%{version}

%build
%cmake
%make_build

%install
%make_install

desktop-file-install --delete-original \
    --dir %{buildroot}%{_datadir}/applications \
    %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/dbus-1/services/%{name}.%{name}.service
%{_datadir}/icons/hicolor/*/apps/%{name}.png
