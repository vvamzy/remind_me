const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('todoApp', {
  version: '0.1.0'
});
