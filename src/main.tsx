import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { useStore } from './store/useStore';
import './styles.css';

// Browser tests read and set the store through the hook they put on the page.
const test = (globalThis as { __CHESS_TEST__?: Record<string, unknown> }).__CHESS_TEST__;
if (test) test.store = useStore;

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
