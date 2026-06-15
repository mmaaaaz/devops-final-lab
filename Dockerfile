FROM nginx:alpine
# Copy the static HTML file into the nginx html directory
COPY index.html /usr/share/nginx/html/index.html

# Change default nginx port to 8080
RUN sed -i 's/listen  *80;/listen 8080;/g' /etc/nginx/conf.d/default.conf

# Expose port 8080
EXPOSE 8080

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
