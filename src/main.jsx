import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AuthProvider, useAuth } from "./context/AuthContext.jsx";
import AuthScreen from "./components/AuthScreen.jsx";
import App from "./components/App.jsx";
import "./styles.css";

function Root() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="loading-screen">
        <div className="auth-logo">
          <span className="logo-br">br</span>
          <span className="logo-ai">AI</span>
          <span className="logo-ny">ny</span>
        </div>
        <p>Carregando...</p>
      </div>
    );
  }

  return user ? <App /> : <AuthScreen />;
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <AuthProvider>
      <Root />
    </AuthProvider>
  </StrictMode>
);
