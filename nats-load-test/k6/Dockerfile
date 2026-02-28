FROM grafana/k6:latest

WORKDIR /scripts
COPY script.js .

ENTRYPOINT ["k6"]
CMD ["run", "script.js"]
