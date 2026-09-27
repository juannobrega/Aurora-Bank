package br.com.aurora.shared.config;

import br.com.aurora.shared.rest.CurrentUserArgumentResolver;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.List;

@Configuration
public class WebConfiguration implements WebMvcConfigurer {

    private final CurrentUserArgumentResolver currentUser;

    public WebConfiguration(CurrentUserArgumentResolver currentUser) {
        this.currentUser = currentUser;
    }

    @Override
    public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
        resolvers.add(currentUser);
    }

    /**
     * O painel Manager roda em manager.pulsaz.com.br e chama a API em
     * bank.pulsaz.com.br — origem cruzada, que o navegador bloqueia sem estes
     * cabeçalhos. Liberado só para o domínio do Manager e o header da chave
     * de admin; nada de credencial de cookie.
     */
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/admin/**")
                .allowedOrigins("https://manager.pulsaz.com.br", "http://localhost:8000")
                .allowedMethods("GET", "POST")
                .allowedHeaders("X-Admin-Key", "Content-Type");
    }
}
