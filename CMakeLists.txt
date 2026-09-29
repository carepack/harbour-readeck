project(harbour-readeck CXX)
cmake_minimum_required(VERSION 3.5)

find_package(Qt5 COMPONENTS Core Network Qml Gui Quick DBus REQUIRED)

include(FindPkgConfig)
pkg_search_module(SAILFISH sailfishapp REQUIRED)

set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_CXX_STANDARD 11)

add_executable(harbour-readeck
    src/main.cpp
    src/readeckclient.cpp
    src/bookmarklistmodel.cpp
    src/sharereceiver.cpp
)

target_compile_definitions(harbour-readeck PRIVATE
    $<$<OR:$<CONFIG:Debug>,$<CONFIG:RelWithDebInfo>>:QT_QML_DEBUG>
)
target_include_directories(harbour-readeck PRIVATE
    "$<BUILD_INTERFACE:${SAILFISH_INCLUDE_DIRS}>"
)
target_link_libraries(harbour-readeck
    Qt5::Quick
    Qt5::Gui
    Qt5::Network
    Qt5::DBus
    ${SAILFISH_LDFLAGS}
)

install(TARGETS harbour-readeck RUNTIME DESTINATION bin)
install(DIRECTORY qml DESTINATION share/harbour-readeck)
install(FILES harbour-readeck.desktop DESTINATION share/applications)
install(FILES dbus/harbour-readeck.harbour-readeck.service DESTINATION share/dbus-1/services)
install(FILES icons/86x86/harbour-readeck.png   DESTINATION share/icons/hicolor/86x86/apps)
install(FILES icons/108x108/harbour-readeck.png DESTINATION share/icons/hicolor/108x108/apps)
install(FILES icons/128x128/harbour-readeck.png DESTINATION share/icons/hicolor/128x128/apps)
install(FILES icons/172x172/harbour-readeck.png DESTINATION share/icons/hicolor/172x172/apps)

FILE(GLOB TsFiles "translations/*.ts")

# The qmake sailfishapp_i18n CONFIG option (used by qmake-based Sailfish
# projects) has no CMake equivalent, so .ts -> .qm compilation has to be
# driven by hand here. Without this, the app has no QTranslator to load
# and falls back to English source strings for everything of its own,
# no matter the system locale, while Silica's own stock UI text (button
# labels the platform provides, etc.) still follows the system locale
# independently -- exactly the inconsistent mixed-language behavior this
# is meant to fix.
find_program(LRELEASE_EXECUTABLE NAMES lrelease-qt5 lrelease)
if(NOT LRELEASE_EXECUTABLE)
    message(FATAL_ERROR "lrelease (Qt Linguist tools) not found; required to compile translations/*.ts")
endif()

set(QM_FILES "")
foreach(TsFile ${TsFiles})
    get_filename_component(TsName ${TsFile} NAME_WE)
    set(QmFile "${CMAKE_CURRENT_BINARY_DIR}/translations/${TsName}.qm")
    add_custom_command(
        OUTPUT ${QmFile}
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/translations"
        COMMAND ${LRELEASE_EXECUTABLE} ${TsFile} -qm ${QmFile}
        DEPENDS ${TsFile}
        COMMENT "Compiling ${TsName}.ts"
    )
    list(APPEND QM_FILES ${QmFile})
endforeach()
add_custom_target(translations ALL DEPENDS ${QM_FILES})

install(FILES ${QM_FILES} DESTINATION share/harbour-readeck/translations)

add_custom_target(distfiles
    SOURCES
        harbour-readeck.desktop
        dbus/harbour-readeck.harbour-readeck.service
        qml/harbour-readeck.qml
        qml/cover/CoverPage.qml
        qml/pages/LoginPage.qml
        qml/pages/BookmarksPage.qml
        qml/pages/BookmarkDetailPage.qml
        qml/pages/BookmarkInfoPage.qml
        qml/pages/PdfLocationDialog.qml
        qml/pages/ImageViewerPage.qml
        qml/pages/AddBookmarkPage.qml
        qml/pages/CaptureContentPage.qml
        qml/pages/SettingsPage.qml
        qml/components/BookmarkDelegate.qml
        qml/js/extractcontent.js
        rpm/harbour-readeck.changes.in
        rpm/harbour-readeck.changes.run.in
        rpm/harbour-readeck.spec
        ${TsFiles})
