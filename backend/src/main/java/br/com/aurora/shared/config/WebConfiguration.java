package br.com.aurora.shared.config;

import br.com.aurora.shared.rest.CurrentUserArgumentResolver;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
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
}
