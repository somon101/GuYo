/* Оболочка для компьютера: открывает те же файлы из www, интернет не нужен. */
const { app, BrowserWindow, Menu } = require('electron');
const path = require('path');
function createWindow() {
  const win = new BrowserWindow({ width: 1360, height: 900, minWidth: 420, minHeight: 600, title: 'Студия аватаров', backgroundColor: '#F3F4FA', icon: path.join(__dirname, '..', 'www', 'icon-512.png'), webPreferences: { contextIsolation: true, sandbox: true } });
  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, '..', 'www', 'index.html'));
}
app.whenReady().then(() => { createWindow(); app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); }); });
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
