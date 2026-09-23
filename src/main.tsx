import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { registerSW } from 'virtual:pwa-register'
import App from './App'
import './styles.css'
import './households.css'

registerSW({immediate:true})
const basename=import.meta.env.BASE_URL.replace(/\/$/,'')
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><BrowserRouter basename={basename}><App/></BrowserRouter></React.StrictMode>)
