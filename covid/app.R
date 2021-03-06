#building my covid app following the shiny tutorial
#set up the app
library(shiny) #required
library(leaflet) #mapping spatial data
library(rgdal) #working with spatial data
library(RSocrata)#for pulling public health data
library(tidyverse)
library(config)#for keeping config file private
library(htmltools) #for tweaking map labels

#pull in shapefile
counties<-readOGR("/Users/ebar/Dropbox/R/covid-dashboard/NYS_Civil_Boundaries_SHP/no_co_counties.shp", layer = "no_co_counties")

#PULL IN PUBLICH HEALTH DATA

nys<-config::get("/Users/ebar/Dropbox/R/covid-dashboard/nys_healthdata") #may need to adjust path

#pull the data
covidData<-read.socrata(
  "https://health.data.ny.gov/resource/xdss-u53e.csv",
  app_token = nys$token,
  email     = nys$email,
  password  = nys$pwd
)
#subset to focal counties
our_counties<-c("Clinton", "Essex", "Franklin", "Hamilton", "Herkimer", "Lewis", "St. Lawrence", "Jefferson")
noco_covid<-covidData %>% filter(county %in% our_counties)

#extract most recent data
no_covid<-noco_covid %>% group_by(county) %>%
  arrange(desc(test_date)) %>% slice(1)

#join health data to shapefile
counties@data<-left_join(counties@data, no_covid, by = c("NAME" = "county"))

#calculate new fields in shapefile
counties@data$cases_per_1000<-(counties@data$cumulative_number_of_positives.x/counties@data$Pop)*1000
counties@data$tests_per_1000<-(counties@data$cumulative_number_of_tests.x/counties@data$Pop)*1000


#set population variable
population<-c(80695,37300,50293,4434,61833,111755,26447,108047)
pop_size<-rep(population, 48)

noco_covid$pop_size<-pop_size
noco_covid$cases_per_cap<-noco_covid$cumulative_number_of_positives/noco_covid$pop_size
noco_covid$cases_per_1000<-noco_covid$cases_per_cap*1000
noco_covid$tests_per_1000<-(noco_covid$cumulative_number_of_tests/noco_covid$pop_size)*1000

#set up bins and color for them
bins<-c(0,0.2,0.4,0.6,0.8, 1.0)
pal<-colorBin("Greens",  bins = bins)

#now set up map labels

labels<-sprintf(
  "<strong>%s</strong><br/>%g cases.",
  counties$NAME, counties$cumulative_number_of_positives) %>% lapply(htmltools::HTML)

#color variable for plots
colors<-c('#ffffe5','#f7fcb9','#d9f0a3','#addd8e','#78c679','#41ab5d','#238443','#005a32')

#build ui ----
ui<-fluidPage(
  titlePanel("North Country Covid Mapper"),
  sidebarLayout(
    sidebarPanel(
      helpText("This application will help you visualize covid data in the North Country"),
      selectInput("variable", "Choose the data to display",
                  choices = c("Total cases",
                              "Cases per 1000 residents",
                              "Total tests",
                              "Tests per 1000 residents"
                              ),
                  selected = "Total cases")
     ),
    mainPanel(
      tabsetPanel(
        tabPanel("Plot view",
                 plotOutput("cases_county")),
        tabPanel("Table view", tableOutput("cases_by_table")),
        tabPanel("Map view", leafletOutput("covid_map"))
      )
    )
  )
)

#define server logic ----
server<-function(input, output) {

  output$cases_county<-renderPlot({
    data<-switch(input$variable,
                 "Total cases" = noco_covid %>% select(test_date, county, cumulative_number_of_positives),
                 "Cases per 1000 residents" = noco_covid %>% select(test_date, county, cases_per_1000),
                 "Total tests" = noco_covid %>% select(test_date, couty, cumulative_number_of_tests),
                 "Tests per 1000 residents" = noco_covid %>% select(test_date, county, tests_per_1000))

    ggplot(data, aes(test_date, cumulative_number_of_positives, group = county, color = county))+
      geom_line()+
      geom_point()+
      scale_color_manual(values = colors)+
      labs(x = "Date", y = "Cumulative number of cases")
  })
  output$cases_by_table<-renderTable({
    noco_covid
  })
  output$covid_map<- renderLeaflet({
  leaflet() %>% #addTiles() %>%
    setView(lng = -75.05, lat = 44.05, zoom = 7) %>%
    addPolygons(
      fillColor = ~pal(cases_per_1000),
      data = counties,
      weight = 2,
      opacity = 1,
      color = "green",
      highlight = highlightOptions(#highlight lets you mouse over a county and have it change color
        weight = 5,
        color = "red",
        bringToFront = T),
      label = labels,
      labelOptions = labelOptions(
        style = list("font-weight" = "normal", padding = "3px 8px"),
        textsize = "15px",
        direction = "auto")
    )

})

}

# Run the app ----
shinyApp(ui = ui, server = server)